import Foundation

/// Platform-neutral ECG samples. HealthKit types must be mapped before this boundary.
///
/// Missing voltage values stay in-place so their timestamps and positions are preserved.
public struct ECGSignal: Codable, Equatable, Sendable {
    /// Canonical model input used by HealthKit, the built-in example and offline adapters.
    public static let formatIdentifier = "watchbeat.ecg.signal.v1"
    public static let schemaVersion = 1

    /// Seconds since the beginning of this ECG recording, in source order.
    public let timeSeconds: [Double]

    /// Apple-Watch-similar-to-Lead-I voltage in millivolts, index-aligned with `timeSeconds`.
    public let voltageMillivolts: [Double?]

    /// Source-declared rate when available. Analysis verifies timing from `timeSeconds` itself.
    public let nominalSamplingRateHz: Double?

    public init(
        timeSeconds: [Double],
        voltageMillivolts: [Double?],
        nominalSamplingRateHz: Double?
    ) {
        self.timeSeconds = timeSeconds
        self.voltageMillivolts = voltageMillivolts
        self.nominalSamplingRateHz = nominalSamplingRateHz
    }
}
