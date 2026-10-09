import ECGCore
import Foundation

/// Persists compact list screening results across launches, so reopening the app only reads and
/// analyzes ECGs added since. Never holds waveforms, reports, acquisition dates or other metadata.
public protocol ECGScreeningCacheStorage: Sendable {
    func load() throws -> [UUID: ECGScreeningSummary]
    func save(_ summaries: [UUID: ECGScreeningSummary]) throws
    func clear() throws
}

public enum ECGScreeningCacheIdentity {
    /// The analysis a cached summary came from. A new algorithm version or any changed research
    /// parameter invalidates every cached summary instead of showing results from older rules.
    public static let current: String = {
        let config = ECGAlgorithmConfig.researchDefaults
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let parameters = (try? encoder.encode(config)).flatMap { String(data: $0, encoding: .utf8) }
        return "\(AlgorithmVersion.semanticVersion)|\(parameters ?? config.schemaVersion)"
    }()
}

/// Same protection as the annotation file: complete file protection and excluded from backup.
/// It lives under Caches because every entry can be recomputed from Apple Health.
public struct ECGScreeningCacheFileStorage: ECGScreeningCacheStorage {
    public let directory: URL
    public let analysisIdentity: String
    public var fileURL: URL { directory.appendingPathComponent("screening-cache-v1.json") }

    private struct Document: Codable {
        let schemaVersion: Int
        let analysisIdentity: String
        let records: [UUID: ECGScreeningSummary]
    }

    public init(directory: URL, analysisIdentity: String = ECGScreeningCacheIdentity.current) {
        self.directory = directory
        self.analysisIdentity = analysisIdentity
    }

    public static func standard() -> ECGScreeningCacheFileStorage {
        ECGScreeningCacheFileStorage(
            directory: URL.cachesDirectory.appendingPathComponent("WatchBeatScreening", isDirectory: true)
        )
    }

    /// Throws only when the file exists but cannot be read (for example while protected data is
    /// locked). A corrupt, older-schema or other-analysis file is disposable and reads as empty.
    public func load() throws -> [UUID: ECGScreeningSummary] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return [:]
        }
        guard let document = try? JSONDecoder().decode(Document.self, from: data),
              document.schemaVersion == 1,
              document.analysisIdentity == analysisIdentity else {
            return [:]
        }
        return document.records
    }

    public func save(_ summaries: [UUID: ECGScreeningSummary]) throws {
        let document = Document(schemaVersion: 1, analysisIdentity: analysisIdentity, records: summaries)
        try ECGProtectedFile.write(JSONEncoder().encode(document), to: fileURL, in: directory)
    }

    public func clear() throws {
        try ECGProtectedFile.remove(fileURL)
    }
}
