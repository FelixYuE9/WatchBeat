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

    @Test func defaultHistoryQueryIsNotTruncatedAtTwoHundredRecords() async {
        let records = (0..<225).map { _ in makeRecord() }
        let repository = ECGRepository(reader: FakeECGReader(records: records))
        guard case .loaded(let all) = await repository.loadRecords(),
              case .loaded(let limited) = await repository.loadRecords(limit: 100) else {
            Issue.record("Expected loaded metadata"); return
        }
        #expect(all.count == 225)
        #expect(limited.count == 100)
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

    // MARK: - Saved screening results

    @Test func savedScreeningSkipsVoltageReadsAfterRelaunch() async {
        let record = makeRecord(declaredMeasurementCount: 1)
        let samples = [ECGVoltageSample(timeSinceSampleStart: 0, quantity: nil)]
        let storage = FakeScreeningCacheStorage()
        let firstLaunch = ECGRepository(
            reader: FakeECGReader(records: [record], voltageSamples: samples),
            screeningStorage: storage
        )
        _ = await firstLaunch.loadRecords()
        let screened = await firstLaunch.loadScreeningSummary(for: record)
        await firstLaunch.flushScreeningCache()

        let reader = FakeECGReader(records: [record], voltageSamples: samples)
        let relaunch = ECGRepository(reader: reader, screeningStorage: storage)
        _ = await relaunch.loadRecords()
        let cached = await relaunch.cachedScreeningSummaries(for: [record])
        let summary = await relaunch.loadScreeningSummary(for: record)
        let fetchCount = await reader.voltageFetchCount()

        #expect(screened == .loaded(.notAnalyzed))
        #expect(cached == [record.id: .notAnalyzed])
        #expect(summary == .loaded(.notAnalyzed))
        #expect(fetchCount == 0)
    }

    @Test func onlyRecordsAddedSinceTheLastLaunchAreUncached() async {
        let known = makeRecord()
        let added = makeRecord()
        let storage = FakeScreeningCacheStorage(summaries: [known.id: .prematureCandidates(count: 2)])
        let repository = ECGRepository(
            reader: FakeECGReader(records: [added, known]),
            screeningStorage: storage
        )

        _ = await repository.loadRecords()
        let cached = await repository.cachedScreeningSummaries(for: [added, known])

        #expect(cached == [known.id: .prematureCandidates(count: 2)])
    }

    @Test func fullHistoryReloadForgetsRecordsNoLongerInHealth() async {
        let kept = makeRecord()
        let removed = makeRecord()
        let storage = FakeScreeningCacheStorage(summaries: [
            kept.id: .noPrematureCandidates,
            removed.id: .prematureCandidates(count: 1)
        ])
        let repository = ECGRepository(reader: FakeECGReader(records: [kept]), screeningStorage: storage)

        _ = await repository.loadRecords(limit: 1)
        let afterLimitedQuery = storage.stored
        _ = await repository.loadRecords()

        #expect(afterLimitedQuery.count == 2)
        #expect(storage.stored == [kept.id: .noPrematureCandidates])
    }

    @Test func unreadableSavedResultsAreNeverOverwrittenWithAPartialCopy() async {
        let record = makeRecord(declaredMeasurementCount: 1)
        let storage = FakeScreeningCacheStorage(summaries: [UUID(): .noPrematureCandidates], failsRead: true)
        let repository = ECGRepository(
            reader: FakeECGReader(
                records: [record],
                voltageSamples: [ECGVoltageSample(timeSinceSampleStart: 0, quantity: nil)]
            ),
            screeningStorage: storage
        )

        _ = await repository.loadScreeningSummary(for: record)
        await repository.flushScreeningCache()
        let savesWhileLocked = storage.saveCount
        storage.allowReads()
        await repository.flushScreeningCache()

        #expect(savesWhileLocked == 0)
        #expect(storage.stored.count == 2)
        #expect(storage.stored[record.id] == .notAnalyzed)
    }

    @Test func clearingSavedResultsRemovesStoredAndInMemorySummaries() async {
        let record = makeRecord()
        let storage = FakeScreeningCacheStorage(summaries: [record.id: .noPrematureCandidates])
        let repository = ECGRepository(reader: FakeECGReader(records: [record]), screeningStorage: storage)

        _ = await repository.loadRecords()
        let cleared = await repository.clearScreeningCache()
        let cached = await repository.cachedScreeningSummaries(for: [record])

        #expect(cleared)
        #expect(cached.isEmpty)
        #expect(storage.stored.isEmpty)
    }

    @Test func screeningCacheFileRoundTripsAndDropsOtherAnalysisVersions() throws {
        let directory = ECGInsightsFixture.temporaryDirectory()
        defer { ECGInsightsFixture.removeDirectory(directory) }
        let summaries: [UUID: ECGScreeningSummary] = [
            UUID(): .prematureCandidates(count: 3),
            UUID(): .noPrematureCandidates,
            UUID(): .notAnalyzed
        ]
        try ECGScreeningCacheFileStorage(directory: directory, analysisIdentity: "rules-a").save(summaries)

        #expect(try ECGScreeningCacheFileStorage(directory: directory, analysisIdentity: "rules-a").load() == summaries)
        #expect(try ECGScreeningCacheFileStorage(directory: directory, analysisIdentity: "rules-b").load().isEmpty)
        #expect(try ECGInsightsFixture.excludedFromBackup(directory))
    }

    @Test func missingOrCorruptScreeningCacheReadsAsEmpty() throws {
        let directory = ECGInsightsFixture.temporaryDirectory()
        defer { ECGInsightsFixture.removeDirectory(directory) }
        let storage = ECGScreeningCacheFileStorage(directory: directory)

        #expect(try storage.load().isEmpty)
        try storage.save([UUID(): .noPrematureCandidates])
        try ECGInsightsFixture.corruptFile(storage.fileURL)
        #expect(try storage.load().isEmpty)
        try storage.clear()
        #expect(try storage.load().isEmpty)
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
