import Foundation

/// Authorization outcomes. HealthKit does not expose a reliable "read denied" status, so this
/// enum deliberately has no `denied` case: an empty query result must never be presented as denial.
public enum ECGAuthorizationOutcome: Equatable, Sendable {
    case unavailable
    case authorizationRequested
    case failed(message: String)
}

public enum ECGListOutcome: Equatable, Sendable {
    case loaded([ECGRecord])
    case noAccessibleRecords
    case unavailable
    case superseded
    case cancelled
    case failed(message: String)
}

public enum ECGMeasurementOutcome: Equatable, Sendable {
    case loaded(ECGMeasurement)
    case superseded
    case cancelled
    case failed(message: String)
}

/// Compact, non-diagnostic result used to annotate the metadata list after an on-device screen.
/// The full voltage signal is deliberately not retained by this value. `ECGScreeningCacheStorage`
/// persists it so a relaunch does not have to read every waveform again.
public enum ECGScreeningSummary: Codable, Equatable, Sendable {
    case noPrematureCandidates
    case prematureCandidates(count: Int)
    case notAnalyzed
}

public enum ECGScreeningOutcome: Equatable, Sendable {
    case loaded(ECGScreeningSummary)
    case cancelled
    case failed(message: String)
}

public enum ECGListState: Equatable, Sendable {
    case idle
    case loading
    case unavailable
    case authorizationRequired
    case noAccessibleRecords
    case loaded([ECGRecord])
    case failed(message: String)
}

public enum ECGDetailState: Equatable, Sendable {
    case idle
    case loading
    case loaded(ECGMeasurement)
    case loadedWithIncompleteMeasurements(ECGMeasurement)
    case failed(message: String)
}
