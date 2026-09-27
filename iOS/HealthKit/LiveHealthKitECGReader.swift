import Foundation
import HealthKit
import WatchBeatModels

/// The only type in the app that touches `HKHealthStore`.
///
/// Read-only: `requestAuthorization` is always called with an empty `toShare` set. Fetched
/// `HKElectrocardiogram` objects are kept in an in-memory index only, and are never written to disk,
/// exported, or logged.
public actor LiveHealthKitECGReader: ECGHealthKitReading {
    private let store: HKHealthStore
    private var samplesByID: [UUID: HKElectrocardiogram] = [:]

    public init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    public nonisolated func isECGDataAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// ECG read authorization only. `toShare` is intentionally empty.
    public func requestReadOnlyAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: [HKObjectType.electrocardiogramType()])
    }

    /// Metadata-only query; no voltage data is loaded here.
    public func fetchECGMetadata(limit: Int) async throws -> [ECGRecord] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [HKSamplePredicate.electrocardiogram()],
            sortDescriptors: [SortDescriptor(\HKElectrocardiogram.startDate, order: .reverse)],
            limit: limit
        )
        let samples = try await descriptor.result(for: store)
        samplesByID = Dictionary(uniqueKeysWithValues: samples.map { ($0.uuid, $0) })
        return samples.map(ECGHealthKitMapper.record(from:))
    }

    /// Streams voltage measurements and stops early when the task is cancelled.
    public func fetchVoltageSamples(forRecordWithID id: UUID) async throws -> [ECGVoltageSample] {
        guard let sample = samplesByID[id] else { throw ECGReaderError.recordNotCached }

        let descriptor = HKElectrocardiogramQueryDescriptor(sample)
        var samples: [ECGVoltageSample] = []
        for try await measurement in descriptor.results(for: store) {
            if Task.isCancelled { throw CancellationError() }
            samples.append(ECGHealthKitMapper.voltageSample(from: measurement))
        }
        return samples
    }
}
