import ECGCore
import Foundation
import WatchBeatModels

/// Orchestrates HealthKit reads behind typed outcomes.
///
/// Two protections are enforced here:
/// - **stale-request protection**: every call takes a generation number; a result whose generation is
///   no longer current is discarded instead of overwriting the newer selection.
/// - **cancellation**: a cancelled task reports `.cancelled` and never writes state.
///
/// No ECG value, HealthKit identifier, or acquisition date is logged or persisted.
public actor ECGRepository {
    private let reader: ECGHealthKitReading
    private var listGeneration = 0
    private var measurementGeneration = 0

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
            let samples = try await reader.fetchVoltageSamples(forRecordWithID: record.id)
            guard !Task.isCancelled else { return .cancelled }
            guard generation == measurementGeneration else { return .superseded }

            let signal = ECGHealthKitMapper.signal(
                from: samples,
                declaredMeasurementCount: record.declaredMeasurementCount,
                declaredSamplingRateHz: record.samplingFrequencyHz
            )

            let integrity: ECGSignalIntegrityReport
            do {
                integrity = try ECGSignalInspector.inspect(signal)
            } catch {
                return .failed(message: Self.sanitizedDescription(of: error))
            }

            let measurement = ECGMeasurement(
                record: record,
                signal: signal,
                integrity: integrity,
                issues: Self.issues(for: samples.count, record: record, integrity: integrity)
            )
            return .loaded(measurement)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(message: Self.sanitizedDescription(of: error))
        }
    }

    // MARK: - Helpers

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
