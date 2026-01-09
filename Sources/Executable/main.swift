import Foundation
import RingRingCLI

@main
struct Main {
    static func main() async {
        let cli = PhoneCallCLI()

        do {
            try await cli.run(arguments: CommandLine.arguments)
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
