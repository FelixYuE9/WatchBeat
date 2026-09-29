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
/// No ECG value, HealthKit identifier, or acquisition date is logged or persisted.
public actor ECGRepository {
    private let reader: ECGHealthKitReading
    private var listGeneration = 0
    private var measurementGeneration = 0
    /// Keeps only compact list annotations, never raw voltage samples or acquisition dates.
    private var screeningCache: [UUID: ECGScreeningSummary] = [:]

    public init(reader: ECGHealthKitReading) {
        self.reader = reader
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

    public func loadRecords(limit: Int = 200) async -> ECGListOutcome {
        guard reader.isECGDataAvailable() else { return .unavailable }

        listGeneration += 1
        let generation = listGeneration
        do {
            let records = try await reader.fetchECGMetadata(limit: limit)
            guard !Task.isCancelled else { return .cancelled }
            guard generation == listGeneration else { return .superseded }
            let currentRecordIDs = Set(records.map(\.id))
            screeningCache = screeningCache.filter { currentRecordIDs.contains($0.key) }
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
            screeningCache[record.id] = measurement.screeningSummary
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
        if let cached = screeningCache[record.id] {
            return .loaded(cached)
        }

        do {
            let measurement = try await makeMeasurement(for: record)
            guard !Task.isCancelled else { return .cancelled }
            let summary = measurement.screeningSummary
            screeningCache[record.id] = summary
            return .loaded(summary)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(message: Self.sanitizedDescription(of: error))
        }
    }

    // MARK: - Helpers

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
