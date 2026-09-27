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
