import Foundation

/// Audio processing utilities for RingRing
public enum AudioUtils {
    /// Convert PCM 16-bit audio to Mu-Law
    /// - Parameter pcmData: 16-bit PCM audio data
    /// - Returns: Mu-Law encoded audio
    public static func pcmToMuLaw(_ pcmData: Data) -> Data {
        var result = Data(count: pcmData.count / 2)
        result.withUnsafeMutableBytes { resultPtr in
            pcmData.withUnsafeBytes { pcmPtr in
                guard let base = resultPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let pcmBase = pcmPtr.baseAddress?.assumingMemoryBound(to: Int16.self) else {
                    return
                }

                for i in 0..<(pcmData.count / 2) {
                    let pcm = pcmBase[i]
                    base[i] = pcmToMuLawSample(pcm)
                }
            }
        }
        return result
    }

    /// Convert a single PCM sample to Mu-Law
    /// - Parameter pcm: 16-bit PCM sample
    /// - Returns: Mu-Law encoded byte
    private static func pcmToMuLawSample(_ pcm: Int16) -> UInt8 {
        let BIAS: Int16 = 0x84
        let CLIP: Int16 = 32635

        var sign = (pcm >> 8) & 0x80
        var sample = pcm
        if sign != 0 {
            sample = -sample
        }
        if sample > CLIP {
            sample = CLIP
        }
        sample += BIAS

        var exponent: Int16 = 7
        var expMask: Int16 = 0x4000
        while (sample & expMask) == 0 && exponent > 0 {
            expMask >>= 1
            exponent -= 1
        }

        let mantissa = (sample >> (exponent + 3)) & 0x0F

        let result = ~(sign | (exponent << 4) | mantissa) & 0xFF
        return UInt8(result)
    }

    /// Resample 24kHz PCM to 8kHz PCM
    /// - Parameter pcmData: 24kHz PCM data
    /// - Returns: 8kHz PCM data
    public static func resample24kTo8k(_ pcmData: Data) -> Data {
        let inputSamples = pcmData.count / 2
        let outputSamples = inputSamples / 3
        var result = Data(count: outputSamples * 2)

        result.withUnsafeMutableBytes { resultPtr in
            pcmData.withUnsafeBytes { pcmPtr in
                guard let base = resultPtr.baseAddress?.assumingMemoryBound(to: Int16.self),
                      let pcmBase = pcmPtr.baseAddress?.assumingMemoryBound(to: Int16.self) else {
                    return
                }

                for i in 0..<outputSamples {
                    // Take every 3rd sample for 3:1 downsampling
                    base[i] = pcmBase[i * 3]
                }
            }
        }
        return result
    }

    /// Extract inbound audio from Twilio media stream message
    /// - Parameter message: JSON message from Twilio WebSocket
    /// - Returns: Base64-decoded audio data for inbound track
    public static func extractInboundAudio(_ message: Data) -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: message) as? [String: Any],
              let media = json["media"] as? [String: Any],
              let track = media["track"] as? String,
              track == "inbound",
              let payload = media["payload"] as? String,
              let data = Data(base64Encoded: payload) else {
            return nil
        }
        return data
    }

    /// Create a media stream message for sending audio
    /// - Parameters:
    ///   - audioData: Mu-Law audio data
    ///   - streamSid: Optional stream ID (required for Twilio)
    /// - Returns: JSON message data
    public static func createMediaMessage(_ audioData: Data, streamSid: String? = nil) -> Data {
        var message: [String: Any] = [
            "event": "media",
            "media": ["payload": audioData.base64EncodedString()]
        ]
        if let streamSid = streamSid {
            message["streamSid"] = streamSid
        }
        return (try? JSONSerialization.data(withJSONObject: message)) ?? Data()
    }
}
