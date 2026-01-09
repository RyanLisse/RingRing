import Foundation
import NIO
import NIOHTTP1
import NIOWebSocket
import NIOFoundationCompat

/// Main manager for phone calls
public actor CallManager {
    private var activeCalls: [String: CallState] = [:]
    private var callControlIdToCallId: [String: String] = [:]
    private var webSocketToCallId: [ObjectIdentifier: String] = [:]
    private var phoneProvider: (any PhoneProvider)?
    private var ttsProvider: (any TTSProvider)?
    private var sttProvider: (any STTProvider)?
    private var config: ServerConfig?
    private var server: NIOSSLServer?
    private var bootstrap: ServerBootstrapProtocol?
    private var eventLoopGroup: EventLoopGroup?
    private var sttSessions: [String: any STTSession] = [:]
    private var wsChannels: [String: Channel] = [:]
    private var nextCallId = 0

    /// Initialize the call manager with configuration
    public func initialize(_ config: ServerConfig) async throws {
        self.config = config

        // Create providers
        switch config.phone.provider {
        case .telnyx:
            phoneProvider = TelnyxProvider()
        case .twilio:
            phoneProvider = TwilioProvider()
        }

        guard let phoneProvider = phoneProvider else {
            throw RingRingError.missingConfiguration("Phone provider")
        }

        try await phoneProvider.initialize(config.phone)

        let tts = OpenAITTS()
        try await tts.initialize(config.tts)
        self.ttsProvider = tts

        let stt = OpenAIRealtimeSTT()
        try await stt.initialize(config.stt)
        self.sttProvider = stt
    }

    /// Start the HTTP/WebSocket server
    public func startServer() async throws {
        guard let config = config else {
            throw RingRingError.missingConfiguration("Configuration")
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.eventLoopGroup = group

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                return channel.pipeline.configureHTTPServerPipeline().flatMap { _ in
                    channel.pipeline.addHandler(WebSocketHandler())
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)

        self.bootstrap = bootstrap

        let channel = try await bootstrap.bind(host: "0.0.0.0", port: config.webhook.port).get()
        print("HTTP/WebSocket server listening on port \(config.webhook.port)", to: &stderrStream)

        // Set up request handler
        try await channel.pipeline.addHandler(HTTPRequestHandler(manager: self))
    }

    /// Initiate a phone call
    public func initiateCall(message: String) async throws -> (callId: String, response: String) {
        guard let config = config,
              let phoneProvider = phoneProvider,
              let sttProvider = sttProvider else {
            throw RingRingError.missingConfiguration("Not initialized")
        }

        let callId = "call-\(nextCallId)-\(Int(Date().timeIntervalSince1970))"
        nextCallId += 1

        // Create STT session
        let sttSession = sttProvider.createSession()
        try await sttSession.connect()
        sttSessions[callId] = sttSession

        // Initiate the call
        let callControlId = try await phoneProvider.initiateCall(
            to: config.userPhoneNumber,
            from: config.phone.phoneNumber,
            webhookUrl: "\(config.webhook.publicUrl)/twiml"
        )

        let state = CallState(
            callId: callId,
            callControlId: callControlId,
            userPhoneNumber: config.userPhoneNumber
        )
        activeCalls[callId] = state
        callControlIdToCallId[callControlId] = callId

        print("Call initiated: \(callControlId) -> \(config.userPhoneNumber)", to: &stderrStream)

        // Wait for connection
        try await waitForConnection(callId: callId, timeoutMs: 15000)

        // Generate and send TTS
        let audioData = try await synthesizeAudio(message)
        try await sendAudio(callId: callId, audioData: audioData)

        // Listen for response
        let response = try await listen(callId: callId)

        state.conversationHistory.append((speaker: .claude, message: message))
        state.conversationHistory.append((speaker: .user, message: response))

        return (callId, response)
    }

    /// Continue an active call
    public func continueCall(callId: String, message: String) async throws -> String {
        guard let state = activeCalls[callId] else {
            throw RingRingError.callNotFound(callId)
        }

        guard state.isHungUp == false else {
            throw RingRingError.callHungUp
        }

        try await speakAndListen(callId: callId, message: message)

        state.conversationHistory.append((speaker: .claude, message: message))

        return state.conversationHistory.last(where: { $0.speaker == .user })?.message ?? ""
    }

    /// Speak without waiting for response
    public func speakOnly(callId: String, message: String) async throws {
        guard let state = activeCalls[callId] else {
            throw RingRingError.callNotFound(callId)
        }

        guard state.isHungUp == false else {
            throw RingRingError.callHungUp
        }

        try await speak(callId: callId, message: message)
        state.conversationHistory.append((speaker: .claude, message: message))
    }

    /// End a call
    public func endCall(callId: String, message: String) async throws -> (durationSeconds: Int) {
        guard let state = activeCalls[callId] else {
            throw RingRingError.callNotFound(callId)
        }

        try await speak(callId: callId, message: message)

        // Wait for audio to finish
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Hang up
        if let phoneProvider = phoneProvider {
            try? await phoneProvider.hangup(callControlId: state.callControlId)
        }

        // Clean up
        sttSessions[callId]?.close()
        wsChannels[callId]?.close()
        activeCalls.removeValue(forKey: callId)
        callControlIdToCallId.removeValue(forKey: state.callControlId)
        sttSessions.removeValue(forKey: callId)
        wsChannels.removeValue(forKey: callId)

        let duration = Int(state.duration)
        return (durationSeconds: duration)
    }

    // MARK: - Internal Helpers

    private func synthesizeAudio(_ text: String) async throws -> Data {
        guard let ttsProvider = ttsProvider else {
            throw RingRingError.missingConfiguration("TTS provider")
        }

        let pcmData = try await ttsProvider.synthesize(text)
        let resampled = AudioUtils.resample24kTo8k(pcmData)
        let muLawData = AudioUtils.pcmToMuLaw(resampled)
        return muLawData
    }

    private func sendAudio(callId: String, audioData: Data) async throws {
        guard let channel = wsChannels[callId] else {
            throw RingRingError.callNotFound(callId)
        }

        let state = activeCalls[callId]

        let chunkSize = 160  // 20ms at 8kHz
        for offset in stride(from: 0, to: audioData.count, by: chunkSize) {
            let chunk = audioData.subdata(in: offset..<min(offset + chunkSize, audioData.count))

            var message: [String: Any] = [
                "event": "media",
                "media": ["payload": chunk.base64EncodedString()]
            ]
            if let streamSid = state?.streamSid {
                message["streamSid"] = streamSid
            }

            if let jsonData = try? JSONSerialization.data(withJSONObject: message) {
                let frame = WebSocketFrame(fin: true, opcode: .text, data: .byteBuffer(jsonData))
                try await channel.writeAndFlush(frame)
            }

            try await Task.sleep(nanoseconds: 18_000_000)  // 18ms
        }

        // Small delay to ensure audio finishes
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    private func speak(callId: String, message: String) async throws {
        let audioData = try await synthesizeAudio(message)
        try await sendAudio(callId: callId, audioData: audioData)
        try await Task.sleep(nanoseconds: 150_000_000)
    }

    private func speakAndListen(callId: String, message: String) async throws -> String {
        try await speak(callId: callId, message: message)
        return try await listen(callId: callId)
    }

    private func listen(callId: String) async throws -> String {
        guard let config = config,
              let sttSession = sttSessions[callId] else {
            throw RingRingError.callNotFound(callId)
        }

        guard let state = activeCalls[callId] else {
            throw RingRingError.callNotFound(callId)
        }

        guard !state.isHungUp else {
            throw RingRingError.callHungUp
        }

        let transcript = try await sttSession.waitForTranscript(timeoutMs: config.transcriptTimeoutMs)

        if state.isHungUp {
            throw RingRingError.callHungUp
        }

        print("[\(callId)] User said: \(transcript)", to: &stderrStream)
        return transcript
    }

    private func waitForConnection(callId: String, timeoutMs: Int) async throws {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < Double(timeoutMs) / 1000.0 {
            guard let state = activeCalls[callId] else {
                throw RingRingError.callNotFound(callId)
            }

            let wsConnected = wsChannels[callId] != nil
            let streamReady = state.streamSid != nil || state.streamingReady

            if wsConnected && streamReady {
                return
            }

            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }

        throw RingRingError.callTimeout
    }

    /// Handle incoming WebSocket connection
    public func handleWebSocketConnection(channel: Channel, callId: String) {
        wsChannels[callId] = channel
        webSocketToCallId[ObjectIdentifier(channel)] = callId
        print("WebSocket connected for call \(callId)", to: &stderrStream)
    }

    /// Handle incoming WebSocket message
    public func handleWebSocketMessage(channel: Channel, data: Data) {
        guard let callId = webSocketToCallId[ObjectIdentifier(channel)] else {
            return
        }

        guard let state = activeCalls[callId],
              let sttSession = sttSessions[callId] else {
            return
        }

        // Check for JSON control messages (Twilio)
        if data.count > 0 && data[0] == 0x7B {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let event = json["event"] as? String {
                switch event {
                case "start":
                    if let streamSid = json["streamSid"] as? String {
                        state.streamSid = streamSid
                        print("[\(callId)] Captured streamSid: \(streamSid)", to: &stderrStream)
                    }
                case "stop":
                    state.isHungUp = true
                default:
                    break
                }
            }
        }

        // Extract and forward audio to STT
        if let audioData = AudioUtils.extractInboundAudio(data) {
            Task {
                try? await sttSession.sendAudio(audioData)
            }
        }
    }

    /// Handle incoming HTTP request
    public func handleHTTPRequest(uri: String, method: String, headers: [(String, String)], body: Data) async throws -> (status: HTTPResponseStatus, headers: [(String, String)], body: Data?) {
        if uri == "/health" {
            let response: [String: Any] = [
                "status": "ok",
                "activeCalls": activeCalls.count
            ]
            let responseData = try JSONSerialization.data(withJSONObject: response)
            return (.ok, [("Content-Type", "application/json")], responseData)
        }

        if uri == "/twiml" && method == "POST" {
            return try await handleWebhook(body: body, headers: headers)
        }

        return (.notFound, [], nil)
    }

    private func handleWebhook(body: Data, headers: [(String: String)]) async throws -> (status: HTTPResponseStatus, headers: [(String, String)], body: Data?) {
        guard let phoneProvider = phoneProvider,
              let config = config else {
            return (.internalServerError, [], nil)
        }

        // Validate signature
        let contentType = headers.first { $0.0.lowercased() == "content-type" }?.1 ?? ""
        let signature = headers.first { $0.0.lowercased() == "x-twilio-signature" }?.1
        let telnyxSignature = headers.first { $0.0.lowercased() == "telnyx-signature-ed25519" }?.1

        let webhookUrl = "\(config.webhook.publicUrl)/twiml"

        let isValid: Bool
        if config.phone.provider == .twilio {
            isValid = try await phoneProvider.validateWebhookSignature(signature: signature, url: webhookUrl, body: body)
        } else {
            isValid = try await phoneProvider.validateWebhookSignature(signature: telnyxSignature, url: webhookUrl, body: body)
        }

        // For ngrok free tier, we may skip strict validation
        // In production, you should enforce this

        let event = try? PhoneWebhookEvent.parse(provider: config.phone.provider, data: body)

        if let event = event {
            switch event {
            case .callAnswered(let callControlId),
                 .callHungUp(let callControlId):
                if let callId = callControlIdToCallId[callControlId] {
                    if var state = activeCalls[callId] {
                        state.isHungUp = true
                        activeCalls[callId] = state
                    }
                }
            case .streamingStarted(let callControlId):
                if let callId = callControlIdToCallId[callControlId] {
                    if var state = activeCalls[callId] {
                        state.streamingReady = true
                        activeCalls[callId] = state

                        // Tell Telnyx to start streaming
                        if config.phone.provider == .telnyx {
                            let streamUrl = "wss://\(URL(string: config.webhook.publicUrl)?.host ?? "localhost")/media-stream"
                            try? await phoneProvider.startStreaming(callControlId: callControlId, streamUrl: streamUrl)
                        }
                    }
                }
            default:
                break
            }
        }

        // Return TwiML or empty response
        let xml = phoneProvider.getStreamConnectXml(streamUrl: "")
        return (.ok, [("Content-Type", "application/xml")], xml.data(using: .utf8))
    }

    /// Shutdown the manager
    public func shutdown() async {
        // End all active calls
        for callId in activeCalls.keys {
            try? await endCall(callId: callId, message: "Shutting down...")
        }

        // Close WebSocket channels
        for channel in wsChannels.values {
            channel.close(promise: nil)
        }

        // Close STT sessions
        for session in sttSessions.values {
            try? await session.close()
        }

        // Close server
        try? await eventLoopGroup?.shutdownGracefully()

        wsChannels.removeAll()
        sttSessions.removeAll()
        activeCalls.removeAll()
        callControlIdToCallId.removeAll()
        webSocketToCallId.removeAll()
    }

    /// Get active call state
    public func getCallState(_ callId: String) -> CallState? {
        activeCalls[callId]
    }

    /// List all active calls
    public func listActiveCalls() -> [CallState] {
        Array(activeCalls.values)
    }
}

// MARK: - HTTP Request Handler

private final class HTTPRequestHandler: ChannelInboundHandler {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias OutboundOut = HTTPServerResponsePart

    private let manager: CallManager
    private var bodyBuffer: Data?
    private var currentRequest: HTTPRequestHead?
    private var currentHeaders: [(String, String)]?

    init(manager: CallManager) {
        self.manager = manager
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)

        switch reqPart {
        case .head(let head):
            currentRequest = head
            currentHeaders = Array(head.headers.map { ($0.name, $1.description) })
            bodyBuffer = Data()

            // Handle WebSocket upgrade
            if head.uri == "/media-stream" && head.method == .GET {
                if let upgradeHeaders = head.headers["upgrade"].first,
                   upgradeHeaders.lowercased() == "websocket" {
                    handleWebSocketUpgrade(context: context, head: head)
                    return
                }
            }

        case .body(var buffer):
            if var bufferData = bodyBuffer {
                bufferData.append(contentsOf: buffer.readableBytesView)
                bodyBuffer = bufferData
            }

        case .end:
            if let request = currentRequest,
               let body = bodyBuffer,
               let headers = currentHeaders {
                Task {
                    let (status, responseHeaders, responseBody) = try! await manager.handleHTTPRequest(
                        uri: request.uri,
                        method: request.method.rawValue,
                        headers: headers,
                        body: body
                    )

                    let head = HTTPResponseHead(
                        version: request.version,
                        status: status,
                        headers: HTTPHeaders(responseHeaders.map { ($0, $1) })
                    )
                    context.write(self.wrapOutboundOut(.head(head)), promise: nil)

                    if let body = responseBody {
                        var buffer = context.channel.allocator.buffer(capacity: body.count)
                        buffer.writeBytes(body)
                        context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                    }

                    context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
                    context.flush()
                }
            }
        }
    }

    private func handleWebSocketUpgrade(context: ChannelHandlerContext, head: HTTPRequestHead) {
        // Simple token-based auth
        guard let query = head.uri.split(separator: "?").last,
              let params = parseQueryString(String(query)),
              let token = params["token"],
              !token.isEmpty else {
            // Send 401
            let responseHead = HTTPResponseHead(
                version: head.version,
                status: .unauthorized,
                headers: HTTPHeaders([("Content-Type", "text/plain")])
            )
            context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
            context.write(self.wrapOutboundOut(.body(.byteBuffer(context.channel.allocator.buffer(string: "Unauthorized"))), promise: nil))
            context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
            context.flush()
            return
        }

        // In production, validate the token
        // For now, extract callId from token or use fallback
        let callId = "call-\(Int(Date().timeIntervalSince1970))"

        // Perform WebSocket handshake
        let responseHeaders = HTTPHeaders([
            ("Upgrade", "websocket"),
            ("Connection", "Upgrade"),
            ("Sec-WebSocket-Accept", generateWebSocketAccept(header.headers["sec-websocket-key"].first ?? ""))
        ])

        let responseHead = HTTPResponseHead(
            version: head.version,
            status: .switchingProtocols,
            headers: responseHeaders
        )

        context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
        context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
        context.flush()

        // Set up WebSocket handling
        Task {
            await manager.handleWebSocketConnection(channel: context.channel, callId: callId)
        }
    }

    private func parseQueryString(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].removingPercentEncoding ?? String(parts[0])
                let value = parts[1].removingPercentEncoding ?? String(parts[1])
                result[key] = value
            }
        }
        return result
    }

    private func generateWebSocketAccept(_ key: String?) -> String {
        guard let key = key else { return "" }
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let combined = key + magic
        let sha1 = Insecure.SHA1.hash(data: combined.data(using: .utf8) ?? Data())
        return Data(sha1).base64EncodedString()
    }
}
