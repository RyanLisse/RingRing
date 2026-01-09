import Foundation

/// Version information for RingRing
public enum RingRingVersion {
    /// Current version
    public static let version = "1.0.0"

    /// Full version string with name
    public static let versionString = "RingRing \(version)"

    /// Command for version output
    public static func printVersion() {
        print(versionString)
    }
}
