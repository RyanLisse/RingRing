import Foundation
import MCP
import RingRingCore

/// RingRing MCP Server - allows Claude to call you on the phone
@MainActor
public final class PhoneCallMCP {
    private let manager: CallManager
    private var server: MCPServer?

    public init(manager: CallManager) {
        self.manager = manager
    }

    /// Run the MCP server
    public func run() async throws {
        // Create MCP server
        server = MCPServer(
            name: "phonecall-mcp",
            version: "1.0.0",
            capabilities: .init(tools: true)
        )

        // Register tools
        server?.registerTool(
            name: "initiate_call",
            description: "Start a phone call with the user. Use when you need voice input, want to report completed work, or need real-time discussion.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "message": [
                        "type": "string",
                        "description": "What you want to say to the user. Be natural and conversational."
                    ]
                ],
                "required": ["message"]
            ]
        ) { [weak self] arguments in
            guard let self = self else {
                throw RingRingError.providerError("Manager not available")
            }

            guard let message = arguments["message"] as? String else {
                throw RingRingError.missingConfiguration("message")
            }

            let result = try await self.manager.initiateCall(message: message)

            return MCPResult(
                content: [
                    .text("""
                        Call initiated successfully.

                        Call ID: \(result.callId)

                        User's response:
                        \(result.response)

                        Use continue_call to ask follow-ups or end_call to hang up.
                        """)
                ]
            )
        }

        server?.registerTool(
            name: "continue_call",
            description: "Continue an active call with a follow-up message.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "call_id": [
                        "type": "string",
                        "description": "The call ID from initiate_call"
                    ],
                    "message": [
                        "type": "string",
                        "description": "Your follow-up message"
                    ]
                ],
                "required": ["call_id", "message"]
            ]
        ) { [weak self] arguments in
            guard let self = self else {
                throw RingRingError.providerError("Manager not available")
            }

            guard let callId = arguments["call_id"] as? String,
                  let message = arguments["message"] as? String else {
                throw RingRingError.missingConfiguration("call_id or message")
            }

            let response = try await self.manager.continueCall(callId: callId, message: message)

            return MCPResult(
                content: [
                    .text("User's response:\n\(response)")
                ]
            )
        }

        server?.registerTool(
            name: "speak_to_user",
            description: "Speak a message on an active call without waiting for a response. Use this to acknowledge requests or provide status updates before starting time-consuming operations.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "call_id": [
                        "type": "string",
                        "description": "The call ID from initiate_call"
                    ],
                    "message": [
                        "type": "string",
                        "description": "What to say to the user"
                    ]
                ],
                "required": ["call_id", "message"]
            ]
        ) { [weak self] arguments in
            guard let self = self else {
                throw RingRingError.providerError("Manager not available")
            }

            guard let callId = arguments["call_id"] as? String,
                  let message = arguments["message"] as? String else {
                throw RingRingError.missingConfiguration("call_id or message")
            }

            try await self.manager.speakOnly(callId: callId, message: message)

            return MCPResult(
                content: [
                    .text("Message spoken: \"\(message)\"")
                ]
            )
        }

        server?.registerTool(
            name: "end_call",
            description: "End an active call with a closing message.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "call_id": [
                        "type": "string",
                        "description": "The call ID from initiate_call"
                    ],
                    "message": [
                        "type": "string",
                        "description": "Your closing message (say goodbye!)"
                    ]
                ],
                "required": ["call_id", "message"]
            ]
        ) { [weak self] arguments in
            guard let self = self else {
                throw RingRingError.providerError("Manager not available")
            }

            guard let callId = arguments["call_id"] as? String,
                  let message = arguments["message"] as? String else {
                throw RingRingError.missingConfiguration("call_id or message")
            }

            let result = try await self.manager.endCall(callId: callId, message: message)

            return MCPResult(
                content: [
                    .text("Call ended. Duration: \(result.durationSeconds)s")
                ]
            )
        }

        // Run server via stdio
        let transport = StdioServerTransport()
        try await server?.run(transport: transport)
    }
}
