# RingRing MCP Server Documentation

This guide covers using RingRing as an MCP (Model Context Protocol) server.

## Overview

RingRing provides an MCP server that allows AI assistants (Claude, GPT, etc.) to make phone calls. The server runs via stdio and exposes tools for initiating, continuing, and ending calls.

## Installation

### Build from Source

```bash
git clone https://github.com/RyanLisse/RingRing.git
cd RingRing
swift build -c release
```

The executable will be at `.build/release/phonecall`.

### Configure Claude Desktop

Edit `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "phonecall": {
      "command": "/path/to/phonecall",
      "args": ["mcp"],
      "env": {
        "CALLME_PHONE_PROVIDER": "telnyx",
        "CALLME_PHONE_ACCOUNT_SID": "your-connection-id",
        "CALLME_PHONE_AUTH_TOKEN": "your-api-key",
        "CALLME_PHONE_NUMBER": "+15551234567",
        "CALLME_USER_PHONE_NUMBER": "+15559876543",
        "CALLME_OPENAI_API_KEY": "sk-...",
        "CALLME_NGROK_AUTHTOKEN": "your-ngrok-token"
      }
    }
  }
}
```

Restart Claude Desktop after adding the configuration.

## MCP Tools

### initiate_call

Start a phone call with the user.

**Use cases:**
- Need voice input or confirmation
- Report completed work
- Discuss decisions
- Real-time consultation

**Parameters:**
```json
{
  "message": "string (required) - What to say to the user"
}
```

**Example:**
```
Please use initiate_call to tell me you've finished the task.
```

**Response:**
```
Call initiated successfully.

Call ID: call-1-1704768000

User's response:
Great, go ahead!

Use continue_call to ask follow-ups or end_call to hang up.
```

### continue_call

Continue an active call with a follow-up message.

**Use cases:**
- Ask follow-up questions
- Provide additional information
- Iterate on decisions

**Parameters:**
```json
{
  "call_id": "string (required) - The call ID from initiate_call",
  "message": "string (required) - Your follow-up message"
}
```

**Example:**
```
Use continue_call with call ID call-1-1704768000 to ask about their preference.
```

### speak_to_user

Speak a message on an active call without waiting for a response.

**Use cases:**
- Acknowledge requests
- Provide status updates
- Signal long-running operations

**Parameters:**
```json
{
  "call_id": "string (required) - The call ID from initiate_call",
  "message": "string (required) - What to say to the user"
}
```

**Example:**
```
Use speak_to_user to say "I'll search for that now, give me a moment."
```

**Pattern:**
```swift
// Speak first (non-blocking)
await speak_to_user(call_id, "Let me search...")

// Do long-running work
let results = await performSearch()

// Continue conversation
await continue_call(call_id, "I found \(results.count) results...")
```

### end_call

End an active call with a closing message.

**Use cases:**
- Conversation is complete
- User wants to hang up
- Disconnecting after task completion

**Parameters:**
```json
{
  "call_id": "string (required) - The call ID from initiate_call",
  "message": "string (required) - Your closing message"
}
```

**Example:**
```
Use end_call to say goodbye and disconnect.
```

## Usage Patterns

### Pattern 1: Simple Call

```
"Call me when you're done analyzing the data."

[AI does work...]

"I'm done. Here's what I found..." (uses initiate_call)
[AI reports results]
"Any questions?" (waits for user)
"Got it, I'll make those changes. Bye!" (uses end_call)
```

### Pattern 2: Decision Point

```
"I need to decide between two approaches."

[AI initiates call]

"I can use approach A (faster) or approach B (more robust). Which do you prefer?"

User: "Go with B, reliability is important."

[AI continues work, then calls back]

"Done. I implemented approach B as requested."
```

### Pattern 3: Multi-Step Collaboration

```
"I'm going to implement the feature. I'll call you at key points."

[Step 1 - initiate_call]
"I've set up the database schema. Should I add indexes?"

User: "Yes, on the user_id field."

[Step 2 - continue_call]
"Indexes added. Now I'm implementing the API. Any specific endpoints?"

User: "Just GET /users and POST /users for now."

[Step 3 - end_call]
"Got it. I'll implement those and test them. I'll call you when tests pass."

[Later - new call]
"Tests are passing. Deploying now. Call you back when done."
```

### Pattern 4: Async Work While Talking

```
[initiate_call]
"I found some issues. Let me check if they're critical."

[speak_to_user]
"Let me verify the impact... please hold."

[AI does analysis - user waits]

[continue_call]
"Good news - these are non-critical display issues. I'll fix them today."

[end_call]
"Perfect. Thanks!"
```

## Tool Selection Guide

| Situation | Recommended Tool |
|-----------|-----------------|
| Need voice input | `initiate_call` |
| Have active call, need response | `continue_call` |
| Have active call, just informing | `speak_to_user` |
| Conversation complete | `end_call` |
| Starting new task | `initiate_call` |

## Error Handling

The MCP server returns errors for:

- **Missing configuration**: Required env vars not set
- **Provider errors**: Phone provider API failures
- **Call timeout**: User didn't respond in time
- **Call hung up**: User disconnected
- **Not found**: Invalid call_id

### Error Response Format

```
Error: Call hung up by user
```

The error is returned as `isError: true` in the MCP response.

## Troubleshooting

### Claude doesn't use the tools

1. Check Claude Desktop logs (Help → Developer → Show Logs)
2. Verify all env vars are set in `settings.json`
3. Restart Claude Desktop
4. Try explicit prompt: "Use the phonecall tool to call me"

### Call doesn't connect

1. Check MCP server stderr output (if accessible)
2. Verify phone provider credentials
3. Ensure ngrok tunnel is working
4. Check webhook URL in provider dashboard

### "Call not found" error

- The call_id may be incorrect
- Call may have timed out
- User may have hung up earlier

### Audio quality issues

- Check internet connection
- Verify OpenAI API key is valid
- Check phone provider's voice quality settings

## Claude Prompts

Here are useful prompts for getting Claude to use RingRing effectively:

### For Status Updates

```
"Call me when you're done with [task]."
"Let me know when [task] is complete, call me."
"Update me via phone call after [task]."
```

### For Decisions

```
"Call me to discuss [topic]."
"I need input on [decision], let's talk about it."
"Let's have a quick call to resolve [issue]."
```

### For Collaboration

```
"Call me after each major milestone in [project]."
"I want to stay updated on [project], call me regularly."
"Let's have a quick call to review [progress]."
```

### For Async Acknowledgment

```
"Use speak_to_user to acknowledge my request, then do the work."
"Tell me you received the request via phonecall, then proceed."
"Call me to say you're starting [task]."
```

## Advanced Configuration

### Custom Timeout

Set a custom transcript timeout:

```json
{
  "env": {
    "CALLME_TRANSCRIPT_TIMEOUT_MS": "300000"
  }
}
```

### Custom Voice

Change the TTS voice:

```json
{
  "env": {
    "CALLME_TTS_VOICE": "nova"
  }
}
```

Available voices: `alloy`, `echo`, `fable`, `onyx`, `nova`, `shimmer`

### Custom Port

Use a different local port:

```json
{
  "env": {
    "CALLME_PORT": "3334"
  }
}
```

## Integration Examples

### With Cursor

Add to Cursor's MCP configuration (Settings → MCP):

```json
{
  "phonecall": {
    "command": "/path/to/phonecall",
    "args": ["mcp"],
    "env": { ... }
  }
}
```

### With Continue.dev

Add to `~/.continue/config.json`:

```json
{
  "mcpServers": [
    {
      "name": "phonecall",
      "command": "/path/to/phonecall",
      "args": ["mcp"],
      "env": { ... }
    }
  ]
}
```

### With Windsurf

Add to Windsurf's MCP configuration:

```json
{
  "phonecall": {
    "command": "/path/to/phonecall",
    "args": ["mcp"],
    "env": { ... }
  }
}
```

## Development

### Running MCP Server Directly

```bash
# With environment variables
CALLME_PHONE_PROVIDER=telnyx \
CALLME_PHONE_ACCOUNT_SID=... \
CALLME_PHONE_AUTH_TOKEN=... \
CALLME_PHONE_NUMBER=... \
CALLME_USER_PHONE_NUMBER=... \
CALLME_OPENAI_API_KEY=... \
phonecall mcp
```

### Debug Mode

For debugging, the MCP server writes logs to stderr:

```json
{
  "command": "/path/to/phonecall",
  "args": ["mcp"],
  "env": { ... }
}
```

View logs in Claude Desktop's developer console or redirect stderr:

```bash
phonecall mcp 2> mcp.log
```

## FAQ

**Q: Can I make multiple calls at once?**
A: Currently, only one active call is supported. Subsequent calls will fail until the current call ends.

**Q: What happens if my phone goes to voicemail?**
A: The STT will timeout (default 3 minutes) and return an error. The call will be automatically ended.

**Q: Can I use RingRing without ngrok?**
A: If you have a public server with a public IP, you can set `CALLME_PUBLIC_URL` to your server's URL. ngrok is only required for development behind NAT.

**Q: Is my conversation private?**
A: Your audio is processed by the phone provider (Telnyx/Twilio) and OpenAI for speech-to-text. Review their privacy policies. The audio is not stored by RingRing.

**Q: Can I use RingRing internationally?**
A: Yes, if your phone provider supports international calling. The phone numbers must be in E.164 format.

## Support

- GitHub Issues: https://github.com/RyanLisse/RingRing/issues
- Documentation: https://github.com/RyanLisse/RingRing
- Original TypeScript version: https://github.com/ZeframLou/call-me
