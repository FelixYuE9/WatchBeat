import ECGCore
import Foundation
import WatchBeatModels

/// Orchestrates HealthKit reads behind typed outcomes.
///
/// Request protections are enforced here:
/// - **stale-request protection**: list reloads and detail selections use separate generation
///   numbers; an old detail result cannot overwrite a newer selection.
/// - **screening isolation**: compact list screening does not advance the detail generation.
/// - **cancellation**: a cancelled task reports `.cancelled` and never writes state.
///
/// No ECG value, HealthKit identifier, or acquisition date is logged. The only thing persisted is
/// the compact screening summary per record UUID, through `screeningStorage`.
public actor ECGRepository {
    private let reader: ECGHealthKitReading
    private let screeningStorage: (any ECGScreeningCacheStorage)?
    private var listGeneration = 0
    private var measurementGeneration = 0
    /// Keeps only compact list annotations, never raw voltage samples or acquisition dates.
    /// Mirrored to `screeningStorage` so a relaunch only screens records added since.
    private var screeningCache: [UUID: ECGScreeningSummary] = [:]
    /// Until the stored cache has been read, saving would overwrite it with a partial copy.
    private var hasLoadedStoredScreening = false
    private var unsavedScreeningCount = 0
    /// Bounds both the work lost if the app is closed mid-screening and the number of file writes.
    private static let screeningSaveBatchSize = 20

    public init(reader: ECGHealthKitReading, screeningStorage: (any ECGScreeningCacheStorage)? = nil) {
        self.reader = reader
        self.screeningStorage = screeningStorage
    }

    public func prepareAuthorization() async -> ECGAuthorizationOutcome {
        guard reader.isECGDataAvailable() else { return .unavailable }
        do {
            try await reader.requestReadOnlyAuthorization()
            return .authorizationRequested
        } catch {
            return .failed(message: Self.sanitizedDescription(of: error))
        }
    }

    public func loadRecords(limit: Int? = nil) async -> ECGListOutcome {
        guard reader.isECGDataAvailable() else { return .unavailable }

        listGeneration += 1
        let generation = listGeneration
        do {
            let records = try await reader.fetchECGMetadata(limit: limit)
            guard !Task.isCancelled else { return .cancelled }
            guard generation == listGeneration else { return .superseded }
            if limit == nil {
                pruneScreeningCache(keeping: Set(records.map(\.id)))
            }
            return records.isEmpty ? .noAccessibleRecords : .loaded(records)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(message: Self.sanitizedDescription(of: error))
        }
    }

    public func loadMeasurements(for record: ECGRecord) async -> ECGMeasurementOutcome {
        guard reader.isECGDataAvailable() else {
            return .failed(message: "healthkit.unavailable")
        }

        measurementGeneration += 1
        let generation = measurementGeneration
        do {
            let measurement = try await makeMeasurement(for: record)
            guard !Task.isCancelled else { return .cancelled }
            guard generation == measurementGeneration else { return .superseded }
            // A detail is opened one at a time, so its new summary is saved right away.
            cacheScreeningSummary(measurement.screeningSummary, for: record.id)
            flushScreeningCache()
            return .loaded(measurement)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(message: Self.sanitizedDescription(of: error))
        }
    }

    /// Loads and analyzes one record for its list annotation without participating in the detail
    /// view's latest-selection generation. This lets a user open a detail while the list continues
    /// screening other records. Only the compact summary is cached.
    public func loadScreeningSummary(for record: ECGRecord) async -> ECGScreeningOutcome {
        guard reader.isECGDataAvailable() else {
            return .failed(message: "healthkit.unavailable")
        }
        loadStoredScreeningIfNeeded()
        if let cached = screeningCache[record.id] {
            return .loaded(cached)
        }

        do {
            let measurement = try await makeMeasurement(for: record)
            guard !Task.isCancelled else { return .cancelled }
            let summary = measurement.screeningSummary
            cacheScreeningSummary(summary, for: record.id)
            return .loaded(summary)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(message: Self.sanitizedDescription(of: error))
        }
    }

    /// Summaries already known for these records, from this session or an earlier launch. The list
    /// shows them at once and only reads voltages for the rest.
    public func cachedScreeningSummaries(for records: [ECGRecord]) -> [UUID: ECGScreeningSummary] {
        loadStoredScreeningIfNeeded()
        var summaries: [UUID: ECGScreeningSummary] = [:]
        for record in records {
            if let summary = screeningCache[record.id] { summaries[record.id] = summary }
        }
        return summaries
    }

    /// Saves summaries that are not yet on disk. The list calls this when a screening pass ends.
    public func flushScreeningCache() {
        guard unsavedScreeningCount > 0 else { return }
        persistScreeningCache()
    }

    /// Removes every cached summary, in memory and on disk. Records are screened again on demand.
    @discardableResult
    public func clearScreeningCache() -> Bool {
        screeningCache.removeAll()
        unsavedScreeningCount = 0
        guard let screeningStorage else { return true }
        do {
            try screeningStorage.clear()
            hasLoadedStoredScreening = true
            return true
        } catch {
            return false
        }
    }

    // MARK: - Helpers

    private func loadStoredScreeningIfNeeded() {
        guard !hasLoadedStoredScreening, let screeningStorage else { return }
        do {
            // Results computed before the stored copy became readable are newer; keep them.
            screeningCache.merge(try screeningStorage.load()) { current, _ in current }
            hasLoadedStoredScreening = true
        } catch {
            // Protected data can be briefly unavailable; retry on the next request.
        }
    }

    private func cacheScreeningSummary(_ summary: ECGScreeningSummary, for id: UUID) {
        guard screeningCache[id] != summary else { return }
        screeningCache[id] = summary
        unsavedScreeningCount += 1
        if unsavedScreeningCount >= Self.screeningSaveBatchSize {
            persistScreeningCache()
        }
    }

    /// Records that were deleted in Health, or are no longer readable, leave no cached result behind.
    private func pruneScreeningCache(keeping currentRecordIDs: Set<UUID>) {
        loadStoredScreeningIfNeeded()
        let kept = screeningCache.filter { currentRecordIDs.contains($0.key) }
        guard kept.count != screeningCache.count else { return }
        screeningCache = kept
        persistScreeningCache()
    }

    private func persistScreeningCache() {
        guard let screeningStorage else {
            unsavedScreeningCount = 0
            return
        }
        loadStoredScreeningIfNeeded()
        guard hasLoadedStoredScreening else { return }
        do {
            try screeningStorage.save(screeningCache)
            unsavedScreeningCount = 0
        } catch {
            // A failed write only means these records are screened again after a relaunch.
        }
    }

    private func makeMeasurement(for record: ECGRecord) async throws -> ECGMeasurement {
        let samples = try await reader.fetchVoltageSamples(forRecordWithID: record.id)
        try Task.checkCancellation()

        let signal = ECGHealthKitMapper.signal(
            from: samples,
            declaredMeasurementCount: record.declaredMeasurementCount,
            declaredSamplingRateHz: record.samplingFrequencyHz
        )
        let integrity = try ECGSignalInspector.inspect(signal)
        return ECGMeasurement(
            record: record,
            signal: signal,
            integrity: integrity,
            issues: Self.issues(for: samples.count, record: record, integrity: integrity)
        )
    }

    private static func issues(
        for loadedCount: Int,
        record: ECGRecord,
        integrity: ECGSignalIntegrityReport
    ) -> [ECGMeasurementIssue] {
        var issues = ECGHealthKitMapper.completenessIssues(
            measurementCount: loadedCount,
            declaredMeasurementCount: record.declaredMeasurementCount
        )

        func append(_ issue: ECGMeasurementIssue) {
            guard !issues.contains(issue) else { return }
            issues.append(issue)
        }

        if !integrity.missingVoltageIndices.isEmpty { append(.missingLeadVoltage) }
        if !integrity.hasStrictlyIncreasingFiniteTimestamps { append(.nonIncreasingTimeOrder) }
        if !integrity.nonFiniteTimeIndices.isEmpty || !integrity.nonFiniteVoltageIndices.isEmpty {
            append(.nonFiniteValue)
        }
        return issues
    }

    /// Error text carries domain and code only. Never ECG values, identifiers, or dates.
    private static func sanitizedDescription(of error: Error) -> String {
        let bridged = error as NSError
        return "\(bridged.domain).\(bridged.code)"
    }
}
