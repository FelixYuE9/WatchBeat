// See ECGHealthKitMapperTests.swift: no `import Foundation` in a file that imports Testing.
import HealthKit
import Testing
import WatchBeatHealthKit
import WatchBeatModels

/// State and request-identity tests for `ECGRepository`.
/// These run against `FakeECGReader`; they are not HealthKit end-to-end evidence.
@Suite struct ECGRepositoryStateTests {

    @Test func unavailableHealthKitReportsUnavailableState() async {
        let repository = ECGRepository(reader: FakeECGReader(isAvailable: false))
        let outcome = await repository.loadRecords()
        #expect(outcome == .unavailable)
    }

    @Test func emptyResultIsNoAccessibleRecordsNotDenial() async {
        let repository = ECGRepository(reader: FakeECGReader(records: []))
        let outcome = await repository.loadRecords()
        #expect(outcome == .noAccessibleRecords)
    }

    @Test func metadataFailureIsReportedAsTypedFailure() async {
        let repository = ECGRepository(
            reader: FakeECGReader(metadataFailure: FakeReaderError(code: "query-refused"))
        )
        let outcome = await repository.loadRecords()

        guard case .failed(let message) = outcome else {
            Issue.record("Expected failure outcome, got \(outcome)")
            return
        }
        #expect(message.contains("FakeReaderError"))
    }

    @Test func authorizationRequestsReadOnlyAccess() async {
        let repository = ECGRepository(reader: FakeECGReader(records: [makeRecord()]))
        let outcome = await repository.prepareAuthorization()
        #expect(outcome == .authorizationRequested)
    }

    @Test func staleMeasurementResultIsDiscarded() async {
        let entry = Gate()
        let hold = Gate()
        let repository = ECGRepository(
            reader: FakeECGReader(voltageSamples: [], entryGate: entry, holdGate: hold)
        )
        let older = makeRecord()
        let newer = makeRecord()

        async let olderOutcome = repository.loadMeasurements(for: older)
        await entry.wait()

        let newerOutcome = await repository.loadMeasurements(for: newer)
        hold.open()
        let discarded = await olderOutcome

        #expect(discarded == .superseded)
        guard case .loaded = newerOutcome else {
            Issue.record("Expected the newer selection to load, got \(newerOutcome)")
            return
        }
    }

    @Test func cancelledMeasurementRequestIsReportedAsCancelled() async {
        let entry = Gate()
        let hold = Gate()
        let repository = ECGRepository(
            reader: FakeECGReader(voltageSamples: [], entryGate: entry, holdGate: hold)
        )

        let task = Task { await repository.loadMeasurements(for: makeRecord()) }
        await entry.wait()
        task.cancel()
        hold.open()

        let outcome = await task.value
        #expect(outcome == .cancelled)
    }

    @Test func incompleteMeasurementsAreReportedSeparatelyFromFailure() async {
        let record = makeRecord(declaredMeasurementCount: 5)
        let samples = [
            ECGVoltageSample(timeSinceSampleStart: 0.0, quantity: nil)
        ]
        let repository = ECGRepository(reader: FakeECGReader(voltageSamples: samples))

        let outcome = await repository.loadMeasurements(for: record)

        guard case .loaded(let measurement) = outcome else {
            Issue.record("Expected a loaded outcome, got \(outcome)")
            return
        }
        #expect(measurement.isComplete == false)
        #expect(measurement.issues.contains(.declaredCountMismatch))
        #expect(measurement.issues.contains(.missingLeadVoltage))
    }

    @Test func listScreeningCachesOnlyTheCompactSummary() async {
        let record = makeRecord(declaredMeasurementCount: 1)
        let reader = FakeECGReader(
            voltageSamples: [ECGVoltageSample(timeSinceSampleStart: 0, quantity: nil)]
        )
        let repository = ECGRepository(reader: reader)

        let first = await repository.loadScreeningSummary(for: record)
        let second = await repository.loadScreeningSummary(for: record)
        let fetchCount = await reader.voltageFetchCount()

        #expect(first == .loaded(.notAnalyzed))
        #expect(second == first)
        #expect(fetchCount == 1)
    }

    @Test func listScreeningDoesNotSupersedeAnOpenedDetail() async {
        let entry = Gate()
        let hold = Gate()
        let repository = ECGRepository(
            reader: FakeECGReader(
                voltageSamples: [ECGVoltageSample(timeSinceSampleStart: 0, quantity: nil)],
                entryGate: entry,
                holdGate: hold
            )
        )

        async let screening = repository.loadScreeningSummary(
            for: makeRecord(declaredMeasurementCount: 1)
        )
        await entry.wait()
        let detail = await repository.loadMeasurements(
            for: makeRecord(declaredMeasurementCount: 1)
        )
        hold.open()
        let screeningResult = await screening

        #expect(screeningResult == .loaded(.notAnalyzed))
        guard case .loaded = detail else {
            Issue.record("Expected an opened detail to load, got \(detail)")
            return
        }
    }

    private func makeRecord(
        declaredMeasurementCount: Int = 3,
        samplingFrequencyHz: Double? = 500
    ) -> ECGRecord {
        let start = Date(timeIntervalSince1970: 0)
        return ECGRecord(
            id: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(30),
            classification: .sinusRhythm,
            averageHeartRateBPM: 60,
            samplingFrequencyHz: samplingFrequencyHz,
            declaredMeasurementCount: declaredMeasurementCount,
            symptomsStatus: .none
        )
    }
}
