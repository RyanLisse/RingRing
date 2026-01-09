# Contributing to RingRing

Thank you for your interest in contributing to RingRing!

## Code of Conduct

Be respectful, inclusive, and constructive. We're building something useful together.

## Getting Started

### Prerequisites

- macOS 14+ (Swift 6 required)
- Xcode 16+ or Swift 6.2+
- Swift Package Manager

### Setting Up

```bash
# Clone the repository
git clone https://github.com/RyanLisse/RingRing.git
cd RingRing

# Build the project
swift build

# Run tests
swift test

# Run the CLI
swift run phonecall init
```

### Development Workflow

1. **Create a branch** for your feature or bugfix:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes** following the code style:
   - Use `swiftformat .` to format code
   - Use `swiftlint` to check linting
   - Follow Swift 6 concurrency best practices

3. **Write tests** for your changes:
   ```bash
   swift test
   ```

4. **Commit your changes**:
   ```bash
   git commit -m "Add feature: description of changes"
   ```

5. **Push and create a Pull Request**:
   ```bash
   git push origin feature/your-feature-name
   ```

## Code Style

### Swift Concurrency

- Use `@MainActor` for CLI and MCP entry points
- Use `actor` for stateful components
- Mark all shared data types as `Sendable`
- Avoid global mutable state

### Naming

- Use clear, descriptive names
- Follow Swift naming conventions (camelCase for properties/functions, PascalCase for types)
- Use meaningful abbreviations only when widely understood

### Documentation

- Document public APIs with inline comments
- Add parameter and return type documentation
- Include usage examples for complex APIs

## Testing

### Unit Tests

Test individual components in isolation:

```swift
func testTelnyxProviderInitiateCall() async throws {
    let provider = TelnyxProvider()
    // Mock HTTP responses and test
}
```

### Integration Tests

Test component interactions:

```swift
func testCallManagerFullFlow() async throws {
    let config = createTestConfig()
    let manager = CallManager()
    try await manager.initialize(config)
    // Test call flow
}
```

### E2E Tests

Test with real services (optional, requires credentials):

```swift
func testRealTelnyxCall() async throws {
    // Only run if credentials are available
    guard hasTelnyxCredentials() else { return }
    // Test real call
}
```

## Project Structure

```
Sources/
├── Core/          # Add new providers here
│   ├── PhoneProvider/  # New phone provider
│   ├── TTS/           # New TTS provider
│   └── STT/           # New STT provider
├── CLI/           # Add new CLI commands
└── MCP/           # Add new MCP tools
```

## Adding a New Phone Provider

1. Implement `PhoneProvider` protocol
2. Create a new folder in `Sources/Core/`
3. Update `PhoneConfig.PhoneProviderType` enum
4. Update `Configuration.swift` to instantiate your provider
5. Add tests

Example:

```swift
public actor MyProvider: PhoneProvider {
    public let name = "myprovider"

    public func initialize(_ config: PhoneConfig) async throws {
        // Initialize with credentials
    }

    // Implement other required methods...
}
```

## Adding a New MCP Tool

1. Register tool in `PhoneCallMCP.swift`
2. Implement handler function
3. Update `docs/MCP.md` with documentation
4. Add tests

Example:

```swift
server?.registerTool(
    name: "my_tool",
    description: "Description of what it does",
    inputSchema: [...]
) { arguments in
    // Handle the tool call
    return MCPResult(content: [...])
}
```

## Adding a New CLI Command

1. Add case to `PhoneCallCLI.run()`
2. Implement handler function
3. Update `README.md` with usage
4. Add tests

Example:

```swift
case "mycommand":
    try await runMyCommand(arguments: Array(arguments.dropFirst(2)))
```

## Release Process

1. Update version in `Sources/Executable/Version.swift`
2. Update `CHANGELOG.md`
3. Create git tag: `git tag v1.0.0`
4. Push tag: `git push origin v1.0.0`
5. GitHub Actions will build and release

## Issues

When reporting issues:

1. Use the issue template
2. Include:
   - macOS version
   - Swift version
   - RingRing version
   - Steps to reproduce
   - Expected vs actual behavior
   - Logs (if applicable)

## Questions?

- Open an issue with the `question` label
- Join our discussions (if available)
- Check existing issues and documentation

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
