import Foundation
import WatchBeatModels

enum ECGInsightsFixture {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    static func date(day: Int, hour: Int = 12) -> Date {
        // Fixed synthetic dates only; no personal acquisition metadata.
        calendar.date(from: DateComponents(year: 2025, month: 1, day: day, hour: hour))
            ?? Date(timeIntervalSince1970: 0)
    }

    static func record(day: Int = 10, hour: Int = 12, heartRate: Double? = 60) -> ECGRecord {
        let start = date(day: day, hour: hour)
        return ECGRecord(
            id: UUID(), startDate: start, endDate: start.addingTimeInterval(30),
            classification: .sinusRhythm, averageHeartRateBPM: heartRate,
            samplingFrequencyHz: 500, declaredMeasurementCount: 15_000, symptomsStatus: .notSet
        )
    }

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("watchbeat-annotation-test-\(UUID())", isDirectory: true)
    }

    static func removeDirectory(_ url: URL) { try? FileManager.default.removeItem(at: url) }
    static func corruptFile(_ url: URL) throws { try Data("invalid-json".utf8).write(to: url) }
    static func fileIsStillCorrupt(_ url: URL) throws -> Bool { try Data(contentsOf: url) == Data("invalid-json".utf8) }
    static func excludedFromBackup(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    }
}

final class FakeAnnotationStorage: ECGAnnotationStorage {
    enum Failure: Error { case requested }
    var records: [UUID: ECGAnnotation] = [:]
    var failsRead = false
    var failsWrite = false
    var saveCount = 0

    func load() throws -> [UUID: ECGAnnotation] {
        if failsRead { throw Failure.requested }
        return records
    }
    func save(_ annotations: [UUID: ECGAnnotation]) throws {
        saveCount += 1
        if failsWrite { throw Failure.requested }
        records = annotations
    }
    func clear() throws {
        if failsWrite { throw Failure.requested }
        records = [:]
    }
}
