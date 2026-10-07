import Foundation

/// Self-reported feelings, deliberately independent of Apple's metadata and the detector.
public enum ECGFeeling: String, CaseIterable, Codable, Sendable, Identifiable {
    case noSymptoms, palpitations, skippedBeats, chestDiscomfort, breathlessness
    case dizziness, fatigue, anxiety

    public var id: String { rawValue }
}

public enum ECGRecordTag: Hashable, Sendable, Identifiable {
    case feeling(ECGFeeling)
    case custom(String)

    public var id: String {
        switch self {
        case .feeling(let feeling): return "feeling:\(feeling.rawValue)"
        case .custom(let name): return "custom:\(ECGAnnotation.tagKey(name))"
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public struct ECGAnnotation: Codable, Equatable, Sendable {
    public var feelings: Set<ECGFeeling>
    public var customTags: [String]
    public var note: String

    public init(feelings: Set<ECGFeeling> = [], customTags: [String] = [], note: String = "") {
        self.feelings = feelings
        self.customTags = customTags
        self.note = note
    }

    public var tags: [ECGRecordTag] {
        ECGFeeling.allCases.filter { feelings.contains($0) }.map { .feeling($0) }
            + normalized.customTags.map { .custom($0) }
    }

    public var isEmpty: Bool { feelings.isEmpty && customTags.isEmpty && note.isEmpty }

    public mutating func toggle(_ feeling: ECGFeeling) {
        if feelings.contains(feeling) {
            feelings.remove(feeling)
        } else if feeling == .noSymptoms {
            feelings = [.noSymptoms]
        } else {
            feelings.remove(.noSymptoms)
            feelings.insert(feeling)
        }
    }

    @discardableResult
    public mutating func addCustomTag(_ name: String) -> Bool {
        let clean = Self.cleanTag(name)
        guard !clean.isEmpty,
              !customTags.contains(where: { Self.tagKey($0) == Self.tagKey(clean) }) else {
            return false
        }
        customTags.append(clean)
        return true
    }

    public var normalized: Self {
        var result = Self(feelings: feelings, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        if result.feelings.count > 1 { result.feelings.remove(.noSymptoms) }
        for tag in customTags { result.addCustomTag(tag) }
        return result
    }

    public static func tagKey(_ name: String) -> String {
        cleanTag(name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func cleanTag(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
