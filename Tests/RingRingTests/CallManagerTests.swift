import Testing
@testable import RingRingCore

@Suite("CallManager Tests")
struct CallManagerTests {
    @Test("Configuration should load from environment")
    func testConfigurationLoading() async throws {
        // Set test environment
        let config = try await Configuration.shared.loadFromEnvironment()

        #expect(config.phone.provider == .telnyx || config.phone.provider == .twilio)
        #expect(!config.userPhoneNumber.isEmpty)
    }

    @Test("Audio utils should convert PCM to Mu-Law")
    func testPCMToMuLaw() {
        let pcmData = Data([0x00, 0x10, 0xFF, 0xF0])  // Dummy PCM data
        let muLawData = AudioUtils.pcmToMuLaw(pcmData)

        // Mu-Law should be half the size of 16-bit PCM
        #expect(muLawData.count == pcmData.count / 2)
    }

    @Test("Audio utils should resample 24k to 8k")
    func testResample24kTo8k() {
        // Create dummy 24kHz PCM data (1 second = 48000 bytes)
        let inputSize = 48000
        var input = Data(count: inputSize)
        input.withUnsafeMutableBytes { ptr in
            for i in 0..<(inputSize / 2) {
                let base = ptr.baseAddress?.assumingMemoryBound(to: Int16.self)
                base?[i] = Int16.random(in: -32768...32767)
            }
        }

        let output = AudioUtils.resample24kTo8k(input)

        // 3:1 downsampling
        #expect(output.count == inputSize / 3)
    }
}
