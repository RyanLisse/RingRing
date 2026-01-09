import Foundation
import CryptoKit

/// Twilio phone provider implementation
public actor TwilioProvider: PhoneProvider {
    public let name = "twilio"
    private var config: PhoneConfig?

    public init() {}

    public func initialize(_ config: PhoneConfig) async throws {
        guard config.provider == .twilio else {
            throw RingRingError.providerError("Invalid provider type for Twilio")
        }
        self.config = config
    }

    public func initiateCall(to: String, from: String, webhookUrl: String) async throws -> String {
        guard let config = config else {
            throw RingRingError.missingConfiguration("Twilio not initialized")
        }

        let url = URL(string: "https://api.twilio.com/2010-04-01/Accounts/\(config.accountSid)/Calls.json")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Twilio uses Basic Auth
        let credentials = "\(config.accountSid):\(config.authToken)"
        let base64Credentials = credentials.data(using: .utf8)?.base64EncodedString() ?? ""
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")

        let requestBody = "To=\(to)&From=\(from)&Url=\(webhookUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        request.httpBody = requestBody.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RingRingError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw RingRingError.providerError("HTTP \(httpResponse.statusCode): \(errorText)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let callSid = json["sid"] as? String else {
            throw RingRingError.providerError("Invalid response format")
        }

        return callSid
    }

    public func hangup(callControlId: String) async throws {
        guard let config = config else {
            throw RingRingError.missingConfiguration("Twilio not initialized")
        }

        let url = URL(string: "https://api.twilio.com/2010-04-01/Accounts/\(config.accountSid)/Calls/\(callControlId).json")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let credentials = "\(config.accountSid):\(config.authToken)"
        let base64Credentials = credentials.data(using: .utf8)?.base64EncodedString() ?? ""
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")

        let requestBody = "Status=completed"
        request.httpBody = requestBody.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RingRingError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 204 else {
            throw RingRingError.providerError("HTTP \(httpResponse.statusCode)")
        }
    }

    public func startStreaming(callControlId: String, streamUrl: String) async throws {
        // Twilio streaming is configured via TwiML in the webhook response
        // This is a no-op for Twilio
    }

    public func getStreamConnectXml(streamUrl: String) -> String {
        #"""
        <?xml version="1.0" encoding="UTF-8"?>
        <Response>
            <Start>
                <Stream url="\#(streamUrl)" />
            </Start>
            <Pause length="60" />
        </Response>
        """#
    }

    public func validateWebhookSignature(signature: String?, url: String, body: Data) async throws -> Bool {
        guard let config = config,
              let signature = signature else {
            return false
        }

        // Twilio uses HMAC-SHA1 signature
        let key = SymmetricKey(data: config.authToken.data(using: .utf8) ?? Data())

        // Twilio signature format: SHA1(url + body)
        var signatureData = url.data(using: .utf8) ?? Data()
        signatureData.append(body)

        let computedHMAC = HMAC<Insecure.SHA1>.authenticationCode(for: signatureData, using: key)
        let computedSignature = Data(computedHMAC).base64EncodedString()

        return computedSignature == signature
    }
}
