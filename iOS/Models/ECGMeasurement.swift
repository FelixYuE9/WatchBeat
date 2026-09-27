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

    public var displayName: String {
        switch self {
        case .noMeasurements: return "No voltage measurements were returned."
        case .missingLeadVoltage: return "Some measurements have no Lead I voltage."
        case .declaredCountMismatch: return "Returned measurement count differs from the declared count."
        case .nonIncreasingTimeOrder: return "Measurement timestamps are not strictly increasing."
        case .nonFiniteValue: return "Measurement contains a non-finite value."
        case .integrityCheckFailed: return "Structural integrity check failed."
        }
    }
}

/// A record plus its mapped, platform-neutral signal and the structural facts about it.
public struct ECGMeasurement: Equatable, Sendable {
    public let record: ECGRecord
    public let signal: ECGSignal
    public let integrity: ECGSignalIntegrityReport
    public let issues: [ECGMeasurementIssue]
    public let source: ECGMeasurementSource

    public init(
        record: ECGRecord,
        signal: ECGSignal,
        integrity: ECGSignalIntegrityReport,
        issues: [ECGMeasurementIssue],
        source: ECGMeasurementSource = .healthKit
    ) {
        self.record = record
        self.signal = signal
        self.integrity = integrity
        self.issues = issues
        self.source = source
    }

    public var isComplete: Bool {
        issues.isEmpty
    }
}
