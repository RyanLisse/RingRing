import Foundation

// MARK: - Call State

/// Represents the state of an active phone call
public struct CallState: Sendable {
    public let callId: String
    public let callControlId: String
    public let userPhoneNumber: String
    public let startTime: Date
    public var conversationHistory: [(speaker: Speaker, message: String)]
    public var isHungUp: Bool
    public var streamSid: String?  // Twilio stream ID
    public var streamingReady: Bool  // Telnyx streaming ready

    public enum Speaker: String, Sendable {
        case claude
        case user
    }

    public init(
        callId: String,
        callControlId: String,
        userPhoneNumber: String,
        startTime: Date = Date(),
        conversationHistory: [(speaker: Speaker, message: String)] = [],
        isHungUp: Bool = false,
        streamSid: String? = nil,
        streamingReady: Bool = false
    ) {
        self.callId = callId
        self.callControlId = callControlId
        self.userPhoneNumber = userPhoneNumber
        self.startTime = startTime
        self.conversationHistory = conversationHistory
        self.isHungUp = isHungUp
        self.streamSid = streamSid
        self.streamingReady = streamingReady
    }

    public var duration: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
}

// MARK: - Provider Configuration

/// Configuration for phone providers (Telnyx/Twilio)
public struct PhoneConfig: Sendable {
    public let provider: PhoneProviderType
    public let accountSid: String  // Telnyx: Connection ID, Twilio: Account SID
    public let authToken: String   // Telnyx: API Key, Twilio: Auth Token
    public let phoneNumber: String

    public enum PhoneProviderType: String, Sendable, Codable {
        case telnyx
        case twilio
    }

    public init(provider: PhoneProviderType, accountSid: String, authToken: String, phoneNumber: String) {
        self.provider = provider
        self.accountSid = accountSid
        self.authToken = authToken
        self.phoneNumber = phoneNumber
    }
}

// MARK: - TTS Configuration

/// Configuration for Text-to-Speech
public struct TTSConfig: Sendable {
    public let apiKey: String
    public let voice: OpenAIVoice
    public let model: String

    public enum OpenAIVoice: String, Sendable, Codable {
        case alloy
        case echo
        case fable
        case onyx
        case nova
        case shimmer
    }

    public init(apiKey: String, voice: OpenAIVoice = .onyx, model: String = "tts-1") {
        self.apiKey = apiKey
        self.voice = voice
        self.model = model
    }
}

// MARK: - STT Configuration

/// Configuration for Speech-to-Text
public struct STTConfig: Sendable {
    public let apiKey: String
    public let apiUrl: String?
    public let model: String
    public let silenceDurationMs: Int

    public init(apiKey: String, apiUrl: String? = nil, model: String = "whisper-1", silenceDurationMs: Int = 800) {
        self.apiKey = apiKey
        self.apiUrl = apiUrl
        self.model = model
        self.silenceDurationMs = silenceDurationMs
    }
}

// MARK: - Webhook Configuration

/// Configuration for webhook/ngrok handling
public struct WebhookConfig: Sendable {
    public let publicUrl: String
    public let port: Int
    public let ngrokAuthToken: String?

    public init(publicUrl: String, port: Int = 3333, ngrokAuthToken: String? = nil) {
        self.publicUrl = publicUrl
        self.port = port
        self.ngrokAuthToken = ngrokAuthToken
    }
}

// MARK: - Server Configuration

/// Complete configuration for the RingRing server
public struct ServerConfig: Sendable {
    public let phone: PhoneConfig
    public let tts: TTSConfig
    public let stt: STTConfig
    public let webhook: WebhookConfig
    public let userPhoneNumber: String
    public let transcriptTimeoutMs: Int

    public init(
        phone: PhoneConfig,
        tts: TTSConfig,
        stt: STTConfig,
        webhook: WebhookConfig,
        userPhoneNumber: String,
        transcriptTimeoutMs: Int = 180_000  // 3 minutes default
    ) {
        self.phone = phone
        self.tts = tts
        self.stt = stt
        self.webhook = webhook
        self.userPhoneNumber = userPhoneNumber
        self.transcriptTimeoutMs = transcriptTimeoutMs
    }
}

// MARK: - Errors

/// Errors specific to RingRing
public enum RingRingError: Error, LocalizedError, Sendable {
    case missingConfiguration(String)
    case providerError(String)
    case networkError(String)
    case callNotFound(String)
    case callTimeout
    case callHungUp
    case transcriptionError(String)
    case synthesisError(String)
    case webhookSignatureInvalid
    case authenticationFailed

    public var errorDescription: String? {
        switch self {
        case .missingConfiguration(let key):
            return "Missing required configuration: \(key)"
        case .providerError(let message):
            return "Provider error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .callNotFound(let callId):
            return "Call not found: \(callId)"
        case .callTimeout:
            return "Call timed out"
        case .callHungUp:
            return "Call was hung up by the user"
        case .transcriptionError(let message):
            return "Transcription error: \(message)"
        case .synthesisError(let message):
            return "Speech synthesis error: \(message)"
        case .webhookSignatureInvalid:
            return "Invalid webhook signature"
        case .authenticationFailed:
            return "Authentication failed"
        }
    }
}
