import Foundation

/// Configuration loader for RingRing
public actor Configuration {
    public static let shared = Configuration()

    private var config: ServerConfig?

    private init() {}

    /// Load configuration from environment variables
    /// - Returns: Loaded server configuration
    public func loadFromEnvironment() throws -> ServerConfig {
        let phoneProviderRaw = getEnv("CALLME_PHONE_PROVIDER", default: "telnyx")
        guard let phoneProvider = PhoneConfig.PhoneProviderType(rawValue: phoneProviderRaw) else {
            throw RingRingError.missingConfiguration("Invalid CALLME_PHONE_PROVIDER: must be 'telnyx' or 'twilio'")
        }

        let phoneAccountSid = try getRequiredEnv("CALLME_PHONE_ACCOUNT_SID")
        let phoneAuthToken = try getRequiredEnv("CALLME_PHONE_AUTH_TOKEN")
        let phoneNumber = try getRequiredEnv("CALLME_PHONE_NUMBER")
        let userPhoneNumber = try getRequiredEnv("CALLME_USER_PHONE_NUMBER")
        let openAIApiKey = try getRequiredEnv("CALLME_OPENAI_API_KEY")
        let ngrokAuthToken = getEnv("CALLME_NGROK_AUTHTOKEN")
        let port = Int(getEnv("CALLME_PORT", default: "3333")) ?? 3333

        // Optional: public URL (can be set externally from ngrok)
        let publicUrl = getEnv("CALLME_PUBLIC_URL", default: "http://localhost:\(port)")

        let phoneConfig = PhoneConfig(
            provider: phoneProvider,
            accountSid: phoneAccountSid,
            authToken: phoneAuthToken,
            phoneNumber: phoneNumber
        )

        let ttsVoiceRaw = getEnv("CALLME_TTS_VOICE", default: "onyx")
        guard let ttsVoice = TTSConfig.OpenAIVoice(rawValue: ttsVoiceRaw) else {
            throw RingRingError.missingConfiguration("Invalid CALLME_TTS_VOICE")
        }

        let ttsConfig = TTSConfig(
            apiKey: openAIApiKey,
            voice: ttsVoice
        )

        let silenceDuration = Int(getEnv("CALLME_STT_SILENCE_DURATION_MS", default: "800")) ?? 800
        let sttConfig = STTConfig(
            apiKey: openAIApiKey,
            silenceDurationMs: silenceDuration
        )

        let webhookConfig = WebhookConfig(
            publicUrl: publicUrl,
            port: port,
            ngrokAuthToken: ngrokAuthToken
        )

        let transcriptTimeout = Int(getEnv("CALLME_TRANSCRIPT_TIMEOUT_MS", default: "180000")) ?? 180000

        self.config = ServerConfig(
            phone: phoneConfig,
            tts: ttsConfig,
            stt: sttConfig,
            webhook: webhookConfig,
            userPhoneNumber: userPhoneNumber,
            transcriptTimeoutMs: transcriptTimeout
        )

        return self.config!
    }

    /// Update the public URL (typically from ngrok)
    /// - Parameter publicUrl: The new public URL
    public func updatePublicUrl(_ publicUrl: String) {
        if var currentConfig = config {
            config = ServerConfig(
                phone: currentConfig.phone,
                tts: currentConfig.tts,
                stt: currentConfig.stt,
                webhook: WebhookConfig(
                    publicUrl: publicUrl,
                    port: currentConfig.webhook.port,
                    ngrokAuthToken: currentConfig.webhook.ngrokAuthToken
                ),
                userPhoneNumber: currentConfig.userPhoneNumber,
                transcriptTimeoutMs: currentConfig.transcriptTimeoutMs
            )
        }
    }

    /// Get the current configuration
    /// - Returns: Current server configuration
    public func getConfiguration() throws -> ServerConfig {
        guard let config = config else {
            throw RingRingError.missingConfiguration("Configuration not loaded")
        }
        return config
    }

    // MARK: - Private Helpers

    private func getRequiredEnv(_ key: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[key] else {
            throw RingRingError.missingConfiguration(key)
        }
        return value
    }

    private func getEnv(_ key: String, default: String = "") -> String {
        ProcessInfo.processInfo.environment[key] ?? `default`
    }
}
