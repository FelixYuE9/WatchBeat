import Foundation
import WatchBeatHealthKit
import WatchBeatModels

public struct FakeReaderError: Error, Equatable, Sendable {
    public let code: String

    public init(code: String) {
        self.code = code
    }
}

/// In-memory replacement for `LiveHealthKitECGReader`.
///
/// Real `HKElectrocardiogram` objects cannot be constructed in tests, so repository behavior is
/// verified through this seam. These tests cover states and request identity only; they are not
/// HealthKit end-to-end evidence.
///
/// `entryGate` is opened by the fake when it enters the first voltage call; `holdGate` is then
/// awaited by the fake. That lets a test hold an older request while a newer one completes.
public actor FakeECGReader: ECGHealthKitReading {
    private let isAvailable: Bool
    private let records: [ECGRecord]
    private let voltageSamples: [ECGVoltageSample]
    private let authorizationFailure: FakeReaderError?
    private let metadataFailure: FakeReaderError?
    private let voltageFailure: FakeReaderError?
    private let entryGate: Gate?
    private let holdGate: Gate?
    private var voltageCallCount = 0

    public init(
        isAvailable: Bool = true,
        records: [ECGRecord] = [],
        voltageSamples: [ECGVoltageSample] = [],
        authorizationFailure: FakeReaderError? = nil,
        metadataFailure: FakeReaderError? = nil,
        voltageFailure: FakeReaderError? = nil,
        entryGate: Gate? = nil,
        holdGate: Gate? = nil
    ) {
        self.isAvailable = isAvailable
        self.records = records
        self.voltageSamples = voltageSamples
        self.authorizationFailure = authorizationFailure
        self.metadataFailure = metadataFailure
        self.voltageFailure = voltageFailure
        self.entryGate = entryGate
        self.holdGate = holdGate
    }

    public nonisolated func isECGDataAvailable() -> Bool { isAvailable }

    public func requestReadOnlyAuthorization() async throws {
        if let authorizationFailure { throw authorizationFailure }
    }

    public func fetchECGMetadata(limit: Int) async throws -> [ECGRecord] {
        if let metadataFailure { throw metadataFailure }
        return records
    }

    public func fetchVoltageSamples(forRecordWithID id: UUID) async throws -> [ECGVoltageSample] {
        let callIndex = voltageCallCount
        voltageCallCount += 1

        // Only the first call is held, so a test can keep an older request in flight.
        if callIndex == 0, let entryGate {
            entryGate.open()
            await holdGate?.wait()
        }
        if let voltageFailure { throw voltageFailure }
        return voltageSamples
    }
}
