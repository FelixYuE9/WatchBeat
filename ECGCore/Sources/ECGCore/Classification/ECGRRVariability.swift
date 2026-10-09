import Foundation

/// Variability of detected RR intervals in one recording, never a confirmed NN/clinical HRV result.
/// Timing plausibility is a range check, not a signal-quality or sinus-rhythm assessment.
public struct ECGRRVariabilityMetrics: Codable, Equatable, Sendable {
    public static let currentVersion = "watchbeat.rr-variability.v1"
    public static let plausibleRangeMilliseconds = 300.0...2_000.0

    public let metricsVersion: String
    public let recordingDurationSeconds: Double
    public let detectedIntervalCount: Int
    public let includedIntervalCount: Int
    public let excludedIntervalCount: Int
    /// Included intervals touching a premature candidate, counted once per interval.
    public let candidateAdjacentIntervalCount: Int
    /// Pairs of included intervals that were adjacent in the original sequence.
    public let successivePairCount: Int
    public let meanRRMilliseconds: Double
    /// Sample standard deviation (n - 1 denominator) of included RR intervals, not SDNN.
    public let sdrrMilliseconds: Double
    /// 100 * SDRR / mean RR. This is not the coefficient of variation of heart rate.
    public let coefficientOfVariationPercent: Double
    /// Descriptive RR analogue of RMSSD; nil if there are no original adjacent pairs.
    public let successiveDifferenceRMSMilliseconds: Double?
    /// Percent of original adjacent included pairs whose absolute difference is > 50 ms.
    public let successiveDifferenceOver50MillisecondsPercent: Double?

    /// A rejected interval remains nil so metrics and plots cannot bridge a gap.
    public static func plausibleIntervals(from beats: [ECGAnalyzedBeat]) -> [Double?] {
        zip(beats, beats.dropFirst()).map { pair in
            let previous = pair.0
            let current = pair.1
            let rr = (current.timeSeconds - previous.timeSeconds) * 1_000
            return rr.isFinite && plausibleRangeMilliseconds.contains(rr) ? rr : nil
        }
    }

    static func measure(
        beats: [ECGAnalyzedBeat], recordingDurationSeconds: Double
    ) -> ECGRRVariabilityMetrics? {
        guard recordingDurationSeconds.isFinite, recordingDurationSeconds > 0 else { return nil }
        let intervals = plausibleIntervals(from: beats)
        let included = intervals.compactMap { $0 }
        guard included.count >= 2 else { return nil }
        let mean = included.reduce(0, +) / Double(included.count)
        let variance = included.reduce(0) { $0 + pow($1 - mean, 2) } / Double(included.count - 1)
        let sdrr = sqrt(variance)
        let differences = zip(intervals, intervals.dropFirst()).compactMap { pair -> Double? in
            guard let previous = pair.0, let current = pair.1 else { return nil }
            return current - previous
        }
        let candidateAdjacentCount = intervals.indices.filter { index in
            intervals[index] != nil && (
                isCandidate(beats[index].classification) || isCandidate(beats[index + 1].classification)
            )
        }.count
        let differenceRMS: Double? = differences.isEmpty ? nil
            : sqrt(differences.reduce(0) { $0 + $1 * $1 } / Double(differences.count))
        // Timestamp roundoff must not count a difference of exactly 50 ms as greater than 50.
        let over50Percent: Double? = differences.isEmpty ? nil
            : 100 * Double(differences.filter { abs($0) > 50 + 1e-9 }.count) / Double(differences.count)

        return ECGRRVariabilityMetrics(
            metricsVersion: currentVersion,
            recordingDurationSeconds: recordingDurationSeconds,
            detectedIntervalCount: intervals.count,
            includedIntervalCount: included.count,
            excludedIntervalCount: intervals.count - included.count,
            candidateAdjacentIntervalCount: candidateAdjacentCount,
            successivePairCount: differences.count,
            meanRRMilliseconds: mean,
            sdrrMilliseconds: sdrr,
            coefficientOfVariationPercent: 100 * sdrr / mean,
            successiveDifferenceRMSMilliseconds: differenceRMS,
            successiveDifferenceOver50MillisecondsPercent: over50Percent
        )
    }

    private static func isCandidate(_ classification: BeatClassification) -> Bool {
        switch classification {
        case .prematureUncertain, .possiblePAC, .possiblePVC: return true
        default: return false
        }
    }
}
