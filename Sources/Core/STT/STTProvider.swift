import Foundation

/// Protocol for Speech-to-Text providers
public protocol STTProvider: Sendable {
    /// The name of the provider
    var name: String { get }

    /// Initialize the provider with configuration
    /// - Parameter config: STT configuration
    func initialize(_ config: STTConfig) async throws

    /// Create a new realtime transcription session
    /// - Returns: A new session for streaming transcription
    func createSession() -> STTSession
}

/// Protocol for a realtime STT session
public protocol STTSession: Sendable {
    /// Connect to the transcription service
    func connect() async throws

    /// Send audio data to the transcription session
    /// - Parameter audio: mu-law audio buffer (8kHz mono)
    func sendAudio(_ audio: Data) async throws

    /// Wait for the next complete transcript
    /// - Parameter timeoutMs: Maximum time to wait in milliseconds
    /// - Returns: The transcribed text
    func waitForTranscript(timeoutMs: Int?) async throws -> String

    /// Set callback for partial transcriptions (streaming)
    /// - Parameter callback: Called with partial transcript
    func onPartial(_ callback: @escaping @Sendable (String) -> Void)

    /// Close the session
    func close() async throws

    /// Check if session is connected
    var isConnected: Bool { get }
}

/// OpenAI Realtime API STT implementation
public actor OpenAIRealtimeSTT: STTProvider {
    public let name = "openai-realtime"
    private var config: STTConfig?

    public init() {}

    public func initialize(_ config: STTConfig) async throws {
        self.config = config
    }

    public func createSession() -> STTSession {
        OpenAIRealtimeSession(config: self.config)
    }
}

/// OpenAI Realtime API session
public actor OpenAIRealtimeSession: STTSession {
    private var config: STTConfig?
    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnectedFlag = false
    private var partialCallback: @Sendable (String) -> Void = { _ in }
    private var currentTranscript: String = ""
    private var continuation: CheckedContinuation<String, Error>?
    private var sessionId: String?

    public init(config: STTConfig?) {
        self.config = config
    }

    public var isConnected: Bool {
        isConnectedFlag
    }

    public func connect() async throws {
        guard let config = config else {
            throw RingRingError.missingConfiguration("STT not initialized")
        }

        let apiUrl = config.apiUrl ?? "wss://api.openai.com/v1/realtime"
        guard let url = URL(string: apiUrl) else {
            throw RingRingError.networkError("Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)

        // Start the task
        webSocketTask?.resume()

        // Send session update
        let sessionUpdate: [String: Any] = [
            "type": "session.update",
            "session": [
                "modalities": ["text", "audio"],
                "instructions": "You are a helpful assistant. Transcribe the user's speech accurately.",
                "voice": "alloy",
                "input_audio_format": "g711_ulaw",  // mu-law
                "output_audio_format": "pcm16",
                "input_audio_transcription": [
                    "model": "whisper-1"
                ],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": config.silenceDurationMs
                ]
            ]
        ]

        let updateData = try JSONSerialization.data(withJSONObject: sessionUpdate)
        let updateMessage = URLSessionWebSocketTask.Message.data(updateData)
        try await webSocketTask?.send(updateMessage)

        // Start listening for messages
        isConnectedFlag = true
        Task {
            await listenForMessages()
        }
    }

    public func sendAudio(_ audio: Data) async throws {
        guard let webSocketTask = webSocketTask else {
            throw RingRingError.transcriptionError("WebSocket not connected")
        }

        let message: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": audio.base64EncodedString()
        ]

        let messageData = try JSONSerialization.data(withJSONObject: message)
        let wsMessage = URLSessionWebSocketTask.Message.data(messageData)
        try await webSocketTask.send(wsMessage)
    }

    public func waitForTranscript(timeoutMs: Int? = nil) async throws -> String {
        guard let config = config else {
            throw RingRingError.missingConfiguration("STT not initialized")
        }

        let timeout = timeoutMs ?? config.silenceDurationMs * 10  // Default 10x silence duration

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                // Wait for the transcript
                try await self.waitForTranscriptInternal()
            }

            group.addTask {
                // Timeout task
                try await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000)
                throw RingRingError.callTimeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func waitForTranscriptInternal() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    public func onPartial(_ callback: @escaping @Sendable (String) -> Void) {
        self.partialCallback = callback
    }

    public func close() async throws {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnectedFlag = false
        continuation?.resume(throwing: RingRingError.callHungUp)
        continuation = nil
    }

    private func listenForMessages() async {
        guard let webSocketTask = webSocketTask else {
            return
        }

        do {
            while !Task.isCancelled && isConnectedFlag {
                let message = try await webSocketTask.receive()

                switch message {
                case .string(let text):
                    await handleMessage(text)
                case .data(let data):
                    // Handle binary messages if any
                    break
                @unknown default:
                    break
                }
            }
        } catch {
            continuation?.resume(throwing: error)
        }
    }

    private func handleMessage(_ text: String) async {
        guard let json = try? JSONSerialization.jsonObject(with: text.data(using: .utf8) ?? Data()) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "session.created":
            sessionId = json["session"] as? [String: Any]?["id"] as? String
        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String {
                currentTranscript = transcript
                continuation?.resume(returning: transcript)
                continuation = nil
            }
        case "conversation.item.input_audio_transcription.failed":
            let error = json["error"] as? [String: Any]
            let message = error?["message"] as? String ?? "Unknown transcription error"
            continuation?.resume(throwing: RingRingError.transcriptionError(message))
            continuation = nil
        case "input_audio_buffer.speech_stopped":
            // Speech detected as stopped by server VAD
            break
        case "input_audio_buffer.speech_started":
            // Speech detected as started
            break
        default:
            break
        }
    }
}
