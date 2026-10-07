// Foundation-dependent helpers live in ECGInsightsTestSupport.swift (CLT Testing overlay workaround).
import HealthKit
import Testing
import WatchBeatModels

@Suite struct ECGRecordInsightsTests {
    @Test func noDiscomfortIsExclusiveButOtherFeelingsAreMultiSelect() {
        var annotation = ECGAnnotation()
        annotation.toggle(.noSymptoms)
        annotation.toggle(.palpitations)
        annotation.toggle(.dizziness)
        #expect(annotation.feelings == [.palpitations, .dizziness])
        annotation.toggle(.noSymptoms)
        #expect(annotation.feelings == [.noSymptoms])
        annotation.toggle(.noSymptoms)
        #expect(annotation.isEmpty)
    }

    @Test func tagsTrimWhitespaceAndDeduplicateAcrossCaseAndAccents() {
        var annotation = ECGAnnotation(note: "  remembered context \n")
        #expect(annotation.addCustomTag("  After   café "))
        #expect(!annotation.addCustomTag("after cafe"))
        #expect(!annotation.addCustomTag(" \n "))
        #expect(annotation.normalized.customTags == ["After café"])
        #expect(annotation.normalized.note == "remembered context")
        #expect(ECGRecordTag.custom("AFTER CAFE") == .custom("After café"))
    }

    @Test func customDatesIncludeWholeEndDayAndRejectReversedDays() {
        var filter = ECGRecordFilter(dateRange: .custom)
        filter.startDate = ECGInsightsFixture.date(day: 5)
        filter.endDate = ECGInsightsFixture.date(day: 10, hour: 0)
        let calendar = ECGInsightsFixture.calendar
        #expect(filter.contains(ECGInsightsFixture.date(day: 5, hour: 0), calendar: calendar))
        #expect(filter.contains(ECGInsightsFixture.date(day: 10, hour: 23), calendar: calendar))
        #expect(!filter.contains(ECGInsightsFixture.date(day: 11, hour: 0), calendar: calendar))
        filter.startDate = ECGInsightsFixture.date(day: 11)
        #expect(!filter.contains(ECGInsightsFixture.date(day: 10), calendar: calendar))
    }

    @Test func lastSevenDaysMeansTodayAndSixPriorCalendarDays() {
        let filter = ECGRecordFilter(dateRange: .last7Days)
        let now = ECGInsightsFixture.date(day: 10)
        let calendar = ECGInsightsFixture.calendar
        #expect(filter.contains(ECGInsightsFixture.date(day: 4, hour: 0), now: now, calendar: calendar))
        #expect(!filter.contains(ECGInsightsFixture.date(day: 3, hour: 23), now: now, calendar: calendar))
        #expect(filter.contains(ECGInsightsFixture.date(day: 10, hour: 23), now: now, calendar: calendar))
        #expect(!filter.contains(ECGInsightsFixture.date(day: 11, hour: 0), now: now, calendar: calendar))
    }

    @Test func calendarRangeHandlesDaylightSavingTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        guard let start = calendar.date(from: DateComponents(year: 2025, month: 3, day: 9)),
              let nextDay = calendar.date(from: DateComponents(year: 2025, month: 3, day: 10)) else {
            Issue.record("Unable to construct the DST fixture"); return
        }
        var filter = ECGRecordFilter(dateRange: .custom)
        filter.startDate = start
        filter.endDate = start
        #expect(nextDay.timeIntervalSince(start) == 23 * 3600)
        #expect(filter.contains(nextDay.addingTimeInterval(-1), calendar: calendar))
        #expect(!filter.contains(nextDay, calendar: calendar))
    }

    @Test func anyTagCombinesWithDateResultAndText() {
        let record = ECGInsightsFixture.record(day: 10)
        let annotation = ECGAnnotation(feelings: [.palpitations], customTags: ["After coffee"], note: "Evening walk")
        var filter = ECGRecordFilter(dateRange: .last7Days)
        filter.tags = [.feeling(.dizziness), .custom("after COFFEE")]
        filter.result = .candidates
        filter.query = "WALK"
        let now = ECGInsightsFixture.date(day: 10)
        #expect(filter.matches(record, annotation: annotation, screening: .result(.prematureCandidates(count: 2)), now: now, calendar: ECGInsightsFixture.calendar))
        #expect(!filter.matches(record, annotation: annotation, screening: .result(.noPrematureCandidates), now: now, calendar: ECGInsightsFixture.calendar))
        filter.query = "missing text"
        #expect(!filter.matches(record, annotation: annotation, screening: .result(.prematureCandidates(count: 2)), now: now, calendar: ECGInsightsFixture.calendar))
    }

    @Test func translatedSymptomTermsCanBeSearched() {
        var filter = ECGRecordFilter()
        filter.query = "心悸"
        #expect(filter.matches(ECGInsightsFixture.record(), annotation: ECGAnnotation(feelings: [.palpitations]), screening: nil, searchTerms: ["心悸", "Palpitations"]))
    }

    @Test func pendingAndUnanalyzableAreNeverZeroCandidateResults() {
        let record = ECGInsightsFixture.record()
        var filter = ECGRecordFilter()
        filter.result = .noCandidates
        let states: [ECGListScreeningState?] = [nil, .checking, .failed, .result(.notAnalyzed)]
        for state in states {
            #expect(!filter.matches(record, annotation: ECGAnnotation(), screening: state))
        }
        filter.result = .pending
        #expect(filter.matches(record, annotation: ECGAnnotation(), screening: nil))
        #expect(filter.matches(record, annotation: ECGAnnotation(), screening: .checking))
        #expect(!filter.matches(record, annotation: ECGAnnotation(), screening: .result(.notAnalyzed)))
    }

    @Test func summarySeparatesCoverageAndCountsOnlyAccessibleAnnotations() {
        let records = (0..<6).map { ECGInsightsFixture.record(day: 10 + $0, heartRate: Double(60 + $0 * 10)) }
        let states: [UUID: ECGListScreeningState] = [
            records[0].id: .result(.prematureCandidates(count: 3)),
            records[1].id: .result(.noPrematureCandidates),
            records[2].id: .result(.notAnalyzed), records[3].id: .failed,
            records[4].id: .checking
        ]
        let annotations: [UUID: ECGAnnotation] = [
            records[0].id: ECGAnnotation(feelings: [.palpitations], customTags: ["Coffee", "coffee"]),
            records[1].id: ECGAnnotation(customTags: ["COFFEE"]),
            records[2].id: ECGAnnotation(note: "Note only"),
            UUID(): ECGAnnotation(customTags: ["Unrelated / synthetic"])
        ]
        let summary = ECGRecordInsights(records: records, screening: states, annotations: annotations, calendar: ECGInsightsFixture.calendar)
        #expect(summary.recordCount == 6)
        #expect(summary.analyzedCount == 2)
        #expect(summary.candidateRecordCount == 1)
        #expect(summary.candidateCount == 3)
        #expect(summary.unableToAnalyzeCount == 1)
        #expect(summary.failedCount == 1)
        #expect(summary.pendingCount == 2)
        #expect(summary.annotatedCount == 3)
        #expect(summary.tagCounts.first?.count == 2)
        #expect(summary.tagCounts.count == 2)
        #expect(summary.averageHeartRateBPM == 85)
        #expect(summary.buckets.count == 6)
        #expect(summary.buckets.map(\.date) == summary.buckets.map(\.date).sorted())
    }

    @Test func heartRateMeanIgnoresMissingNonFiniteAndNonPositiveValues() {
        let values: [Double?] = [nil, .nan, .infinity, 0, -1, 60, 80]
        let records = values.map { ECGInsightsFixture.record(heartRate: $0) }
        let summary = ECGRecordInsights(records: records, screening: [:], annotations: [:])
        #expect(summary.heartRateRecordCount == 2)
        #expect(summary.averageHeartRateBPM == 70)
        let empty = ECGRecordInsights(records: [], screening: [:], annotations: [:])
        #expect(empty.averageHeartRateBPM == nil)
        #expect(empty.buckets.isEmpty)
    }

    @Test @MainActor func fileAnnotationsSurviveRelaunchAndCanBeCleared() throws {
        let directory = ECGInsightsFixture.temporaryDirectory()
        defer { ECGInsightsFixture.removeDirectory(directory) }
        let storage = ECGAnnotationFileStorage(directory: directory)
        let store = ECGAnnotationStore(storage: storage)
        let id = UUID()
        let annotation = ECGAnnotation(feelings: [.fatigue], customTags: ["after walk"], note: "Felt tired")
        #expect(store.save(annotation, for: id))
        #expect(try ECGInsightsFixture.excludedFromBackup(directory))
        let reloaded = ECGAnnotationStore(storage: storage)
        #expect(reloaded.annotation(for: id) == annotation)
        #expect(reloaded.clear())
        #expect(try storage.load().isEmpty)
    }

    @Test @MainActor func corruptFileCannotBeSilentlyOverwritten() throws {
        let directory = ECGInsightsFixture.temporaryDirectory()
        defer { ECGInsightsFixture.removeDirectory(directory) }
        let storage = ECGAnnotationFileStorage(directory: directory)
        try storage.save([:])
        try ECGInsightsFixture.corruptFile(storage.fileURL)
        let store = ECGAnnotationStore(storage: storage)
        #expect(store.hasLoadFailure)
        #expect(!store.save(ECGAnnotation(note: "new note"), for: UUID()))
        #expect(try ECGInsightsFixture.fileIsStillCorrupt(storage.fileURL))
        #expect(store.clear())
        #expect(!store.hasLoadFailure)
    }

    @Test @MainActor func failedSaveDoesNotPublishUnsavedEditsAndCanRetry() {
        let storage = FakeAnnotationStorage()
        let store = ECGAnnotationStore(storage: storage)
        let id = UUID()
        #expect(store.save(ECGAnnotation(note: "Original"), for: id))
        storage.failsWrite = true
        #expect(!store.save(ECGAnnotation(note: "Unsaved"), for: id))
        #expect(store.annotation(for: id).note == "Original")
        #expect(store.hasSaveFailure)
        storage.failsWrite = false
        #expect(store.save(ECGAnnotation(note: "Updated"), for: id))
        #expect(store.annotation(for: id).note == "Updated")
        #expect(!store.hasSaveFailure)
        #expect(store.save(ECGAnnotation(), for: id))
        #expect(store.annotations.isEmpty)
    }

    @Test @MainActor func failedReadBlocksWritesUntilSuccessfulReload() {
        let storage = FakeAnnotationStorage()
        storage.failsRead = true
        let store = ECGAnnotationStore(storage: storage)
        #expect(!store.save(ECGAnnotation(note: "new note"), for: UUID()))
        #expect(storage.saveCount == 0)
        storage.failsRead = false
        store.reload()
        #expect(store.save(ECGAnnotation(note: "saved after retry"), for: UUID()))
        store.exampleAnnotation = ECGAnnotation(note: "Synthetic session note")
        #expect(storage.records.values.allSatisfy { $0.note != "Synthetic session note" })
    }
}
