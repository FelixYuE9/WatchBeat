import Foundation

/// Apple's own ECG classification. Display and export only; never an input to research algorithms.
public enum ECGAppleClassification: String, Codable, CaseIterable, Sendable, Equatable {
    case notSet
    case sinusRhythm
    case atrialFibrillation
    case inconclusiveLowHeartRate
    case inconclusiveHighHeartRate
    case inconclusivePoorReading
    case inconclusiveOther
    case unrecognized
}

public enum ECGSymptomsStatus: String, Codable, CaseIterable, Sendable, Equatable {
    case notSet
    case none
    case present
}

/// Metadata-only view of one HealthKit ECG record. No voltage data is held here.
///
/// `id` is the HealthKit sample UUID. It is used as an in-memory key only: it is never persisted,
/// exported, or logged.
public struct ECGRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let startDate: Date
    public let endDate: Date
    public let classification: ECGAppleClassification
    public let averageHeartRateBPM: Double?
    public let samplingFrequencyHz: Double?
    public let declaredMeasurementCount: Int
    public let symptomsStatus: ECGSymptomsStatus

    public init(
        id: UUID,
        startDate: Date,
        endDate: Date,
        classification: ECGAppleClassification,
        averageHeartRateBPM: Double?,
        samplingFrequencyHz: Double?,
        declaredMeasurementCount: Int,
        symptomsStatus: ECGSymptomsStatus
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.classification = classification
        self.averageHeartRateBPM = averageHeartRateBPM
        self.samplingFrequencyHz = samplingFrequencyHz
        self.declaredMeasurementCount = declaredMeasurementCount
        self.symptomsStatus = symptomsStatus
    }

    public var durationSeconds: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
}
