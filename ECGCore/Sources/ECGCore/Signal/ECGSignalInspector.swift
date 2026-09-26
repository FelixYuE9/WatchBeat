import Foundation

public enum ECGSignalInspectionError: Error, Equatable, Sendable {
    case mismatchedSampleCounts(timeCount: Int, voltageCount: Int)
}

/// Structural facts about an ECG. This is intentionally not the full signal-quality gate.
public struct ECGSignalIntegrityReport: Equatable, Sendable {
    public let sampleCount: Int
    public let missingVoltageIndices: [Int]
    public let nonFiniteTimeIndices: [Int]
    public let nonFiniteVoltageIndices: [Int]
    public let duplicateTimestampIndices: [Int]
    public let decreasingTimestampIndices: [Int]
    public let medianSamplingIntervalSeconds: Double?
    public let inferredSamplingRateHz: Double?
    public let samplingIntervalRelativeMAD: Double?

    public var hasStrictlyIncreasingFiniteTimestamps: Bool {
        nonFiniteTimeIndices.isEmpty
            && duplicateTimestampIndices.isEmpty
            && decreasingTimestampIndices.isEmpty
    }

    public init(
        sampleCount: Int,
        missingVoltageIndices: [Int],
        nonFiniteTimeIndices: [Int],
        nonFiniteVoltageIndices: [Int],
        duplicateTimestampIndices: [Int],
        decreasingTimestampIndices: [Int],
        medianSamplingIntervalSeconds: Double?,
        inferredSamplingRateHz: Double?,
        samplingIntervalRelativeMAD: Double?
    ) {
        self.sampleCount = sampleCount
        self.missingVoltageIndices = missingVoltageIndices
        self.nonFiniteTimeIndices = nonFiniteTimeIndices
        self.nonFiniteVoltageIndices = nonFiniteVoltageIndices
        self.duplicateTimestampIndices = duplicateTimestampIndices
        self.decreasingTimestampIndices = decreasingTimestampIndices
        self.medianSamplingIntervalSeconds = medianSamplingIntervalSeconds
        self.inferredSamplingRateHz = inferredSamplingRateHz
        self.samplingIntervalRelativeMAD = samplingIntervalRelativeMAD
    }
}

public enum ECGSignalInspector {
    /// Inspects sample alignment and infers a rate from the median positive timestamp delta.
    /// No sample is removed, sorted, or interpolated.
    public static func inspect(_ signal: ECGSignal) throws -> ECGSignalIntegrityReport {
        guard signal.timeSeconds.count == signal.voltageMillivolts.count else {
            throw ECGSignalInspectionError.mismatchedSampleCounts(
                timeCount: signal.timeSeconds.count,
                voltageCount: signal.voltageMillivolts.count
            )
        }

        var missingVoltageIndices: [Int] = []
        var nonFiniteTimeIndices: [Int] = []
        var nonFiniteVoltageIndices: [Int] = []
        var duplicateTimestampIndices: [Int] = []
        var decreasingTimestampIndices: [Int] = []
        var positiveFiniteDeltas: [Double] = []

        for index in signal.timeSeconds.indices {
            if !signal.timeSeconds[index].isFinite {
                nonFiniteTimeIndices.append(index)
            }

            if let voltage = signal.voltageMillivolts[index] {
                if !voltage.isFinite {
                    nonFiniteVoltageIndices.append(index)
                }
            } else {
                missingVoltageIndices.append(index)
            }

            guard index > signal.timeSeconds.startIndex else { continue }
            let previousTime = signal.timeSeconds[index - 1]
            let currentTime = signal.timeSeconds[index]
            guard previousTime.isFinite, currentTime.isFinite else { continue }

            let delta = currentTime - previousTime
            if delta == 0 {
                duplicateTimestampIndices.append(index)
            } else if delta < 0 {
                decreasingTimestampIndices.append(index)
            } else {
                positiveFiniteDeltas.append(delta)
            }
        }

        let medianDelta = median(of: positiveFiniteDeltas)
        let inferredRate = medianDelta.flatMap { $0 > 0 ? 1.0 / $0 : nil }
        let relativeMAD = medianDelta.flatMap { delta -> Double? in
            guard delta > 0 else { return nil }
            let absoluteDeviations = positiveFiniteDeltas.map { abs($0 - delta) }
            return median(of: absoluteDeviations).map { $0 / delta }
        }

        return ECGSignalIntegrityReport(
            sampleCount: signal.timeSeconds.count,
            missingVoltageIndices: missingVoltageIndices,
            nonFiniteTimeIndices: nonFiniteTimeIndices,
            nonFiniteVoltageIndices: nonFiniteVoltageIndices,
            duplicateTimestampIndices: duplicateTimestampIndices,
            decreasingTimestampIndices: decreasingTimestampIndices,
            medianSamplingIntervalSeconds: medianDelta,
            inferredSamplingRateHz: inferredRate,
            samplingIntervalRelativeMAD: relativeMAD
        )
    }

    private static func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2.0
        }
        return sorted[middle]
    }
}
