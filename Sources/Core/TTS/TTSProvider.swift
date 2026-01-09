import Foundation

/// Protocol for Text-to-Speech providers
public protocol TTSProvider: Sendable {
    /// The name of the provider
    var name: String { get }

    /// Initialize the provider with configuration
    /// - Parameter config: TTS configuration
    func initialize(_ config: TTSConfig) async throws

    /// Convert text to speech
    /// - Parameter text: Text to synthesize
    /// - Returns: PCM audio buffer (16-bit, mono, 24kHz)
    func synthesize(_ text: String) async throws -> Data

    /// Stream TTS audio as chunks arrive (optional, for lower latency)
    /// - Parameter text: Text to synthesize
    /// - Returns: Async stream of PCM audio chunks
    func synthesizeStream(_ text: String) -> AsyncStream<Data>
}

/// OpenAI TTS implementation
public actor OpenAITTS: TTSProvider {
    public let name = "openai"
    private var config: TTSConfig?

    public init() {}

    public func initialize(_ config: TTSConfig) async throws {
        self.config = config
    }

    public func synthesize(_ text: String) async throws -> Data {
        guard let config = config else {
            throw RingRingError.missingConfiguration("TTS not initialized")
        }

        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": config.model,
            "input": text,
            "voice": config.voice.rawValue,
            "response_format": "pcm",  // 16-bit PCM
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RingRingError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw RingRingError.synthesisError("HTTP \(httpResponse.statusCode): \(errorText)")
        }

        return data
    }

    public func synthesizeStream(_ text: String) -> AsyncStream<Data> {
        AsyncStream { continuation in
            Task {
                do {
                    let data = try await synthesize(text)
                    // For simplicity, send the whole thing. Could implement true streaming
                    // using OpenAI's streaming response format if needed.
                    continuation.yield(data)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
