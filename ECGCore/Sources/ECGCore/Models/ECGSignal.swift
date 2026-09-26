import Foundation

/// Platform-neutral ECG samples. HealthKit types must be mapped before this boundary.
///
/// Missing voltage values stay in-place so their timestamps and positions are preserved.
public struct ECGSignal: Codable, Equatable, Sendable {
    public let timeSeconds: [Double]
    public let voltageMillivolts: [Double?]
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
