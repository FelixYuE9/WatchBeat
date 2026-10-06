import Foundation

/// Peak-to-trough voltage of the original samples around one detected R peak.
///
/// The window is fixed at ±80 ms so it spans the QRS deflections (Q, R, S) without reaching the
/// P or T wave at ordinary heart rates. Values are measured on the unfiltered input, i.e. what the
/// user sees on screen. This is a descriptive single-lead measurement, not a clinical voltage
/// criterion: wrist contact and arm posture change it between recordings.
public struct ECGQRSAmplitude: Equatable, Sendable {
    public static let halfWindowMilliseconds = 80.0

    public let maximumSampleIndex: Int
    public let minimumSampleIndex: Int
    public let maximumMillivolts: Double
    public let minimumMillivolts: Double

    public init(
        maximumSampleIndex: Int,
        minimumSampleIndex: Int,
        maximumMillivolts: Double,
        minimumMillivolts: Double
    ) {
        self.maximumSampleIndex = maximumSampleIndex
        self.minimumSampleIndex = minimumSampleIndex
        self.maximumMillivolts = maximumMillivolts
        self.minimumMillivolts = minimumMillivolts
    }

    public var peakToTroughMillivolts: Double {
        maximumMillivolts - minimumMillivolts
    }

    /// Returns `nil` when the inputs are invalid or the window holds no finite voltage.
    /// Missing samples inside the window are skipped, never interpolated.
    public static func measure(
        voltageMillivolts: [Double?],
        around centerIndex: Int,
        samplingFrequencyHz: Double,
        halfWindowMilliseconds: Double = ECGQRSAmplitude.halfWindowMilliseconds
    ) -> ECGQRSAmplitude? {
        guard voltageMillivolts.indices.contains(centerIndex),
              samplingFrequencyHz.isFinite,
              samplingFrequencyHz > 0,
              halfWindowMilliseconds.isFinite,
              halfWindowMilliseconds >= 0 else {
            return nil
        }

        let radius = Int((halfWindowMilliseconds * samplingFrequencyHz / 1_000).rounded())
        let lower = max(voltageMillivolts.startIndex, centerIndex - radius)
        let upper = min(voltageMillivolts.endIndex - 1, centerIndex + radius)
        var maximum: (index: Int, value: Double)?
        var minimum: (index: Int, value: Double)?

        for index in lower...upper {
            guard let value = voltageMillivolts[index], value.isFinite else { continue }
            if maximum.map({ value > $0.value }) ?? true {
                maximum = (index, value)
            }
            if minimum.map({ value < $0.value }) ?? true {
                minimum = (index, value)
            }
        }

        guard let maximum, let minimum else { return nil }
        return ECGQRSAmplitude(
            maximumSampleIndex: maximum.index,
            minimumSampleIndex: minimum.index,
            maximumMillivolts: maximum.value,
            minimumMillivolts: minimum.value
        )
    }
}
