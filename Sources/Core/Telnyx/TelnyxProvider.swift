import Foundation
import CryptoKit

/// Telnyx phone provider implementation
public actor TelnyxProvider: PhoneProvider {
    public let name = "telnyx"
    private var config: PhoneConfig?

    public init() {}

    public func initialize(_ config: PhoneConfig) async throws {
        guard config.provider == .telnyx else {
            throw RingRingError.providerError("Invalid provider type for Telnyx")
        }
        self.config = config
    }

    public func initiateCall(to: String, from: String, webhookUrl: String) async throws -> String {
        guard let config = config else {
            throw RingRingError.missingConfiguration("Telnyx not initialized")
        }

        let url = URL(string: "https://api.telnyx.com/v2/calls")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "to": to,
            "from": from,
            "webhook_url": webhookUrl,
            "webhook_url_method": "POST",
            "connection_id": config.accountSid,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RingRingError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw RingRingError.providerError("HTTP \(httpResponse.statusCode): \(errorText)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let callControlId = json["data"] as? [String: Any]?["call_control_id"] as? String else {
            throw RingRingError.providerError("Invalid response format")
        }

        return callControlId
    }

    public func hangup(callControlId: String) async throws {
        guard let config = config else {
            throw RingRingError.missingConfiguration("Telnyx not initialized")
        }

        let url = URL(string: "https://api.telnyx.com/v2/calls/\(callControlId)/actions/hangup")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RingRingError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 202 else {
            throw RingRingError.providerError("HTTP \(httpResponse.statusCode)")
        }
    }

    public func startStreaming(callControlId: String, streamUrl: String) async throws {
        guard let config = config else {
            throw RingRingError.missingConfiguration("Telnyx not initialized")
        }

        let url = URL(string: "https://api.telnyx.com/v2/calls/\(callControlId)/actions/stream")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "stream_url": streamUrl,
            "stream_track": "inbound",
            "format": "ULAW",
            "sample_rate": 8000,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RingRingError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 202 else {
            throw RingRingError.providerError("HTTP \(httpResponse.statusCode)")
        }
    }

    public func getStreamConnectXml(streamUrl: String) -> String {
        // Telnyx doesn't use TwiML - streaming is initiated via API
        // This is a placeholder for webhook response
        return #"<?xml version="1.0" encoding="UTF-8"?><Response></Response>"#
    }

    public func validateWebhookSignature(signature: String?, url: String, body: Data) async throws -> Bool {
        // Telnyx uses Ed25519 signature
        // For now, we'll implement basic validation
        // In production, you should verify with the public key
        return true
    }
}
