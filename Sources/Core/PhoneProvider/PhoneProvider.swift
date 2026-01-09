import Foundation

/// Protocol for phone providers (Telnyx, Twilio)
public protocol PhoneProvider: Sendable {
    /// The name of the provider (e.g., "telnyx", "twilio")
    var name: String { get }

    /// Initialize the provider with configuration
    /// - Parameter config: Phone configuration
    func initialize(_ config: PhoneConfig) async throws

    /// Initiate an outbound call
    /// - Parameters:
    ///   - to: Destination phone number (E.164 format)
    ///   - from: Source phone number (E.164 format)
    ///   - webhookUrl: URL for webhook callbacks
    /// - Returns: Call control ID from the provider
    func initiateCall(to: String, from: String, webhookUrl: String) async throws -> String

    /// Hang up an active call
    /// - Parameter callControlId: The call control ID
    func hangup(callControlId: String) async throws

    /// Start media streaming for a call
    /// - Parameters:
    ///   - callControlId: The call control ID
    ///   - streamUrl: WebSocket URL for media stream
    func startStreaming(callControlId: String, streamUrl: String) async throws

    /// Get XML response for connecting media stream (used in webhooks)
    /// - Parameter streamUrl: WebSocket URL for media stream
    /// - Returns: XML string for the provider
    func getStreamConnectXml(streamUrl: String) -> String

    /// Validate webhook signature
    /// - Parameters:
    ///   - signature: Signature from webhook headers
    ///   - url: The full URL that received the webhook
    ///   - body: The webhook body
    /// - Returns: true if signature is valid
    func validateWebhookSignature(signature: String?, url: String, body: Data) async throws -> Bool
}

// MARK: - Phone Webhook Event Types

/// Events from phone provider webhooks
public enum PhoneWebhookEvent: Sendable {
    case callInitiated(callControlId: String)
    case callAnswered(callControlId: String)
    case callHungUp(callControlId: String)
    case callBusy(callControlId: String)
    case callNoAnswer(callControlId: String)
    case callFailed(callControlId: String)
    case streamingStarted(callControlId: String)
    case streamingStopped(callControlId: String)
    case unknown(eventType: String)

    /// Parse webhook event data from a provider
    /// - Parameters:
    ///   - provider: The phone provider type
    ///   - data: Raw event data
    /// - Returns: Parsed event type
    public static func parse(provider: PhoneConfig.PhoneProviderType, data: Data) throws -> PhoneWebhookEvent {
        switch provider {
        case .telnyx:
            return try parseTelnyxEvent(data: data)
        case .twilio:
            return try parseTwilioEvent(data: data)
        }
    }

    private static func parseTelnyxEvent(data: Data) throws -> PhoneWebhookEvent {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let eventType = json?["data"] as? [String: Any],
              let eventTypeName = eventType["event_type"] as? String,
              let payload = eventType["payload"] as? [String: Any],
              let callControlId = payload["call_control_id"] as? String else {
            return .unknown(eventType: "invalid")
        }

        switch eventTypeName {
        case "call.initiated":
            return .callInitiated(callControlId: callControlId)
        case "call.answered":
            return .callAnswered(callControlId: callControlId)
        case "call.hangup":
            return .callHungUp(callControlId: callControlId)
        case "call.busy":
            return .callBusy(callControlId: callControlId)
        case "call.no_answer":
            return .callNoAnswer(callControlId: callControlId)
        case "call.failed":
            return .callFailed(callControlId: callControlId)
        case "streaming.started":
            return .streamingStarted(callControlId: callControlId)
        case "streaming.stopped":
            return .streamingStopped(callControlId: callControlId)
        default:
            return .unknown(eventType: eventTypeName)
        }
    }

    private static func parseTwilioEvent(data: Data) throws -> PhoneWebhookEvent {
        // Twilio sends form-urlencoded data
        let body = String(data: data, encoding: .utf8) ?? ""
        let params = body.split(separator: "&")
            .reduce(into: [String: String]()) { dict, pair in
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let key = parts[0].removingPercentEncoding ?? String(parts[0])
                    let value = parts[1].removingPercentEncoding ?? String(parts[1])
                    dict[key] = value
                }
            }

        guard let callSid = params["CallSid"],
              let callStatus = params["CallStatus"] else {
            return .unknown(eventType: "invalid")
        }

        switch callStatus {
        case "in-progress", "ringing":
            return .callAnswered(callControlId: callSid)
        case "completed":
            return .callHungUp(callControlId: callSid)
        case "busy":
            return .callBusy(callControlId: callSid)
        case "no-answer":
            return .callNoAnswer(callControlId: callSid)
        case "failed":
            return .callFailed(callControlId: callSid)
        default:
            return .unknown(eventType: callStatus)
        }
    }
}
