import Foundation

public enum ECGListScreeningState: Equatable, Sendable {
    case checking
    case result(ECGScreeningSummary)
    case failed

    public var isFlagged: Bool {
        guard case .result(.prematureCandidates(let count)) = self else { return false }
        return count > 0
    }
}

public enum ECGDateRange: String, CaseIterable, Identifiable, Sendable {
    case all, last7Days, last30Days, custom
    public var id: String { rawValue }
}

public enum ECGResultFilter: String, CaseIterable, Identifiable, Sendable {
    case all, candidates, noCandidates, unableToAnalyze, pending, failed
    public var id: String { rawValue }
}

public struct ECGRecordFilter: Equatable, Sendable {
    public var dateRange: ECGDateRange
    public var startDate: Date
    public var endDate: Date
    public var result: ECGResultFilter = .all
    /// Multiple selected tags mean ANY tag; all other criteria combine with AND.
    public var tags: Set<ECGRecordTag> = []
    public var query = ""

    public init(dateRange: ECGDateRange = .all, now: Date = Date()) {
        self.dateRange = dateRange
        self.startDate = Calendar.current.date(byAdding: .day, value: -29, to: now) ?? now
        self.endDate = now
    }

    public func matches(
        _ record: ECGRecord,
        annotation: ECGAnnotation,
        screening: ECGListScreeningState?,
        now: Date = Date(),
        calendar: Calendar = .current,
        searchTerms: [String] = []
    ) -> Bool {
        guard contains(record.startDate, now: now, calendar: calendar) else { return false }
        switch result {
        case .all: break
        case .candidates: guard screening?.isFlagged == true else { return false }
        case .noCandidates: guard screening == .result(.noPrematureCandidates) else { return false }
        case .unableToAnalyze: guard screening == .result(.notAnalyzed) else { return false }
        case .pending: guard screening == nil || screening == .checking else { return false }
        case .failed: guard screening == .failed else { return false }
        }
        if !tags.isEmpty && tags.isDisjoint(with: Set(annotation.tags)) { return false }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty {
            let text = ([annotation.note] + annotation.customTags
                + annotation.feelings.map(\.rawValue) + searchTerms).joined(separator: " ")
            guard text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { return false }
        }
        return true
    }

    public func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard dateRange != .all else { return true }
        let firstDay: Date
        let lastDay: Date
        switch dateRange {
        case .all: return true
        case .last7Days, .last30Days:
            let days = dateRange == .last7Days ? 6 : 29
            firstDay = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
            lastDay = calendar.startOfDay(for: now)
        case .custom:
            firstDay = calendar.startOfDay(for: startDate)
            lastDay = calendar.startOfDay(for: endDate)
            guard firstDay <= lastDay else { return false }
        }
        guard let endExclusive = calendar.date(byAdding: .day, value: 1, to: lastDay) else { return false }
        return date >= firstDay && date < endExclusive
    }
}

public struct ECGInsightBucket: Identifiable, Sendable {
    public let date: Date
    public let recordCount: Int
    public let candidateRecordCount: Int
    public let averageHeartRateBPM: Double?
    public var id: Date { date }
}

public struct ECGTagCount: Identifiable, Sendable {
    public let tag: ECGRecordTag
    public let count: Int
    public var id: String { tag.id }
}

/// Descriptive summaries of sampled recordings, never whole-day burden or causal inference.
public struct ECGRecordInsights: Sendable {
    public let recordCount: Int
    public let analyzedCount: Int
    public let candidateRecordCount: Int
    public let candidateCount: Int
    public let unableToAnalyzeCount: Int
    public let pendingCount: Int
    public let failedCount: Int
    public let averageHeartRateBPM: Double?
    public let heartRateRecordCount: Int
    public let annotatedCount: Int
    public let buckets: [ECGInsightBucket]
    public let tagCounts: [ECGTagCount]

    public init(
        records: [ECGRecord],
        screening: [UUID: ECGListScreeningState],
        annotations: [UUID: ECGAnnotation],
        calendar: Calendar = .current,
        groupByMonth: Bool = false
    ) {
        recordCount = records.count
        var analyzed = 0, flagged = 0, candidates = 0, unable = 0, pending = 0, failed = 0
        var tags: [ECGRecordTag: Int] = [:]
        var annotated = 0
        for record in records {
            switch screening[record.id] {
            case .result(.prematureCandidates(let count)):
                analyzed += 1
                if count > 0 { flagged += 1; candidates += count }
            case .result(.noPrematureCandidates): analyzed += 1
            case .result(.notAnalyzed): unable += 1
            case .failed: failed += 1
            case .checking, nil: pending += 1
            }
            let annotation = (annotations[record.id] ?? ECGAnnotation()).normalized
            if !annotation.isEmpty { annotated += 1 }
            for tag in annotation.tags { tags[tag, default: 0] += 1 }
        }
        analyzedCount = analyzed
        candidateRecordCount = flagged
        candidateCount = candidates
        unableToAnalyzeCount = unable
        pendingCount = pending
        failedCount = failed
        annotatedCount = annotated
        let heartRates = Self.heartRates(records)
        heartRateRecordCount = heartRates.count
        averageHeartRateBPM = Self.mean(heartRates)
        tagCounts = tags.map { ECGTagCount(tag: $0.key, count: $0.value) }.sorted {
            $0.count == $1.count ? $0.tag.id < $1.tag.id : $0.count > $1.count
        }
        let groups = Dictionary(grouping: records) { record in
            groupByMonth
                ? (calendar.dateInterval(of: .month, for: record.startDate)?.start ?? calendar.startOfDay(for: record.startDate))
                : calendar.startOfDay(for: record.startDate)
        }
        buckets = groups.map { date, entries in
            ECGInsightBucket(
                date: date,
                recordCount: entries.count,
                candidateRecordCount: entries.filter { screening[$0.id]?.isFlagged == true }.count,
                averageHeartRateBPM: Self.mean(Self.heartRates(entries))
            )
        }.sorted { $0.date < $1.date }
    }

    private static func heartRates(_ records: [ECGRecord]) -> [Double] {
        records.compactMap(\.averageHeartRateBPM).filter { $0.isFinite && $0 > 0 }
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
