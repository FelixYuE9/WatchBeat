import ECGCore
import Foundation

public enum ECGMeasurementSource: String, Codable, Sendable, Equatable {
    case healthKit
    case builtInSyntheticExample
}

/// Facts that make a loaded measurement sequence unsuitable for analysis, kept separate from
/// "no data at all" and from query failures.
public enum ECGMeasurementIssue: String, Codable, CaseIterable, Sendable, Equatable {
    case noMeasurements
    case missingLeadVoltage
    case declaredCountMismatch
    case nonIncreasingTimeOrder
    case nonFiniteValue
    case integrityCheckFailed
}

/// A record plus its mapped, platform-neutral signal and the structural facts about it.
public struct ECGMeasurement: Equatable, Sendable {
    public let record: ECGRecord
    public let signal: ECGSignal
    public let integrity: ECGSignalIntegrityReport
    public let issues: [ECGMeasurementIssue]
    public let source: ECGMeasurementSource
    /// Every source, including the built-in example, is analyzed through this same report contract.
    public let analysis: ECGAnalysisReport
    /// Wall-clock time spent in `analyzer.analyze`, for on-device performance checks only.
    /// Not part of the exported analysis contract.
    public let analysisDurationSeconds: Double

    public init(
        record: ECGRecord,
        signal: ECGSignal,
        integrity: ECGSignalIntegrityReport,
        issues: [ECGMeasurementIssue],
        source: ECGMeasurementSource = .healthKit,
        analyzer: any ECGAnalyzing = PrematureBeatAnalyzer()
    ) {
        self.record = record
        self.signal = signal
        self.integrity = integrity
        self.issues = issues
        self.source = source
        let start = ContinuousClock.now
        self.analysis = analyzer.analyze(signal)
        let elapsed = (ContinuousClock.now - start).components
        self.analysisDurationSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }

    public var isComplete: Bool {
        issues.isEmpty
    }
}
