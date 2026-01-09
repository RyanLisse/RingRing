# RingRing API Reference

This document describes the core APIs used in RingRing.

## Core Module (`RingRingCore`)

### Models

#### `CallState`

Represents the state of an active phone call.

```swift
public struct CallState: Sendable {
    public let callId: String
    public let callControlId: String
    public let userPhoneNumber: String
    public let startTime: Date
    public var conversationHistory: [(speaker: Speaker, message: String)]
    public var isHungUp: Bool
    public var streamSid: String?
    public var streamingReady: Bool

    public enum Speaker: String, Sendable {
        case claude
        case user
    }
}
```

#### `PhoneConfig`

Configuration for phone providers (Telnyx/Twilio).

```swift
public struct PhoneConfig: Sendable {
    public let provider: PhoneProviderType
    public let accountSid: String
    public let authToken: String
    public let phoneNumber: String

    public enum PhoneProviderType: String, Sendable, Codable {
        case telnyx
        case twilio
    }
}
```

#### `TTSConfig`

Configuration for Text-to-Speech.

```swift
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
}
```

#### `STTConfig`

Configuration for Speech-to-Text.

```swift
public struct STTConfig: Sendable {
    public let apiKey: String
    public let apiUrl: String?
    public let model: String
    public let silenceDurationMs: Int
}
```

#### `ServerConfig`

Complete configuration for the RingRing server.

```swift
public struct ServerConfig: Sendable {
    public let phone: PhoneConfig
    public let tts: TTSConfig
    public let stt: STTConfig
    public let webhook: WebhookConfig
    public let userPhoneNumber: String
    public let transcriptTimeoutMs: Int
}
```

### Protocols

#### `PhoneProvider`

Protocol for phone providers (Telnyx, Twilio).

```swift
public protocol PhoneProvider: Sendable {
    var name: String { get }
    func initialize(_ config: PhoneConfig) async throws
    func initiateCall(to: String, from: String, webhookUrl: String) async throws -> String
    func hangup(callControlId: String) async throws
    func startStreaming(callControlId: String, streamUrl: String) async throws
    func getStreamConnectXml(streamUrl: String) -> String
    func validateWebhookSignature(signature: String?, url: String, body: Data) async throws -> Bool
}
```

#### `TTSProvider`

Protocol for Text-to-Speech providers.

```swift
public protocol TTSProvider: Sendable {
    var name: String { get }
    func initialize(_ config: TTSConfig) async throws
    func synthesize(_ text: String) async throws -> Data
    func synthesizeStream(_ text: String) -> AsyncStream<Data>
}
```

#### `STTProvider`

Protocol for Speech-to-Text providers.

```swift
public protocol STTProvider: Sendable {
    var name: String { get }
    func initialize(_ config: STTConfig) async throws
    func createSession() -> STTSession
}
```

#### `STTSession`

Protocol for a realtime STT session.

```swift
public protocol STTSession: Sendable {
    func connect() async throws
    func sendAudio(_ audio: Data) async throws
    func waitForTranscript(timeoutMs: Int?) async throws -> String
    func onPartial(_ callback: @escaping @Sendable (String) -> Void)
    func close() async throws
    var isConnected: Bool { get }
}
```

### CallManager

Main manager for phone calls.

```swift
public actor CallManager {
    public func initialize(_ config: ServerConfig) async throws
    public func startServer() async throws
    public func initiateCall(message: String) async throws -> (callId: String, response: String)
    public func continueCall(callId: String, message: String) async throws -> String
    public func speakOnly(callId: String, message: String) async throws
    public func endCall(callId: String, message: String) async throws -> (durationSeconds: Int)
    public func shutdown() async
    public func getCallState(_ callId: String) -> CallState?
    public func listActiveCalls() -> [CallState]
}
```

### Configuration

Configuration loader for RingRing.

```swift
public actor Configuration {
    public static let shared = Configuration()
    public func loadFromEnvironment() throws -> ServerConfig
    public func updatePublicUrl(_ publicUrl: String)
    public func getConfiguration() throws -> ServerConfig
}
```

### AudioUtils

Audio processing utilities.

```swift
public enum AudioUtils {
    public static func pcmToMuLaw(_ pcmData: Data) -> Data
    public static func resample24kTo8k(_ pcmData: Data) -> Data
    public static func extractInboundAudio(_ message: Data) -> Data?
    public static func createMediaMessage(_ audioData: Data, streamSid: String?) -> Data
}
```

## CLI Module (`RingRingCLI`)

### PhoneCallCLI

Main CLI interface.

```swift
@MainActor
public struct PhoneCallCLI {
    public init()
    public func run(arguments: [String]) async throws
}
```

## MCP Module (`RingRingMCP`)

### PhoneCallMCP

MCP server implementation.

```swift
@MainActor
public final class PhoneCallMCP {
    public init(manager: CallManager)
    public func run() async throws
}
```

## MCP Tools

### `initiate_call`

Start a phone call with the user.

```json
{
  "name": "initiate_call",
  "description": "Start a phone call with the user. Use when you need voice input, want to report completed work, or need real-time discussion.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "message": {
        "type": "string",
        "description": "What you want to say to the user. Be natural and conversational."
      }
    },
    "required": ["message"]
  }
}
```

**Response:**
```
Call initiated successfully.

Call ID: call-1-1704768000

User's response:
I understand, go ahead.

Use continue_call to ask follow-ups or end_call to hang up.
```

### `continue_call`

Continue an active call with a follow-up message.

```json
{
  "name": "continue_call",
  "description": "Continue an active call with a follow-up message.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "call_id": {
        "type": "string",
        "description": "The call ID from initiate_call"
      },
      "message": {
        "type": "string",
        "description": "Your follow-up message"
      }
    },
    "required": ["call_id", "message"]
  }
}
```

### `speak_to_user`

Speak a message on an active call without waiting for a response.

```json
{
  "name": "speak_to_user",
  "description": "Speak a message on an active call without waiting for a response. Use this to acknowledge requests or provide status updates before starting time-consuming operations.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "call_id": {
        "type": "string",
        "description": "The call ID from initiate_call"
      },
      "message": {
        "type": "string",
        "description": "What to say to the user"
      }
    },
    "required": ["call_id", "message"]
  }
}
```

### `end_call`

End an active call with a closing message.

```json
{
  "name": "end_call",
  "description": "End an active call with a closing message.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "call_id": {
        "type": "string",
        "description": "The call ID from initiate_call"
      },
      "message": {
        "type": "string",
        "description": "Your closing message (say goodbye!)"
      }
    },
    "required": ["call_id", "message"]
  }
}
```

## HTTP Endpoints

### `GET /health`

Health check endpoint.

**Response:**
```json
{
  "status": "ok",
  "activeCalls": 1
}
```

### `POST /twiml`

Webhook endpoint for phone providers.

Handles:
- Telnyx JSON webhooks
- Twilio form-urlencoded webhooks

Returns TwiML or empty JSON response.

## WebSocket Endpoints

### `WS /media-stream?token=<token>`

WebSocket endpoint for media streaming.

**Authentication:**
- Token-based authentication
- Token is included in the call initiation

**Message Format (Twilio):**
```json
{
  "event": "media",
  "media": {
    "payload": "<base64-encoded mu-law audio>",
    "track": "inbound"
  },
  "streamSid": "..."
}
```

**Message Format (sending audio):**
```json
{
  "event": "media",
  "media": {
    "payload": "<base64-encoded mu-law audio>"
  },
  "streamSid": "..."
}
```
