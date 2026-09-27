import Foundation
import WatchBeatModels

/// The injectable HealthKit boundary. Implementations keep `HKElectrocardiogram` objects internal;
/// callers only ever see mapped values.
public protocol ECGHealthKitReading: Sendable {
    /// False when HealthKit is not available on this device.
    func isECGDataAvailable() -> Bool

    /// Requests ECG **read** access only. Implementations must pass an empty `toShare` set.
    func requestReadOnlyAuthorization() async throws

    /// Metadata-only list query, sorted by start date (most recent first).
    func fetchECGMetadata(limit: Int) async throws -> [ECGRecord]

    /// Lazily loads the voltage measurements of a previously listed record.
    /// Implementations must throw `CancellationError` when the current task is cancelled.
    func fetchVoltageSamples(forRecordWithID id: UUID) async throws -> [ECGVoltageSample]
}

public enum ECGReaderError: Error, Equatable, Sendable {
    /// The record was not part of the last metadata query, so no in-memory sample reference exists.
    case recordNotCached
    case recordNotFound
}
