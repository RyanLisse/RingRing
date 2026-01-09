# Changelog

All notable changes to RingRing will be documented in this file.

## [Unreleased]

### Added
- Initial Swift implementation of call-me
- Full MCP server support with 4 tools
- CLI with init wizard, call command, and status check
- Telnyx and Twilio phone provider support
- OpenAI TTS and Realtime STT integration
- HTTP/WebSocket server for webhooks and media streaming
- Audio processing (PCM to Mu-Law, resampling)
- Webhook signature validation
- Interactive call mode with CLI
- Swift 6 concurrency with strict safety
- Peekaboo architecture (Core/CLI/MCP separation)

### Documentation
- README with quick start guide
- API reference
- Architecture documentation
- MCP server guide
- Environment variable reference

---

## [1.0.0] - 2026-01-09

### Initial Release
- Port of call-me TypeScript project to Swift
- MCP server for Claude Desktop/Cursor
- CLI tool for direct usage
- Full support for Telnyx and Twilio
- Multi-turn voice conversations
- ngrok tunneling for webhook support
