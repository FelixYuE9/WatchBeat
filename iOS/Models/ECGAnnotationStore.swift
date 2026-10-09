import Foundation
import Observation

public protocol ECGAnnotationStorage {
    func load() throws -> [UUID: ECGAnnotation]
    func save(_ annotations: [UUID: ECGAnnotation]) throws
    func clear() throws
}

/// Only annotations and their association keys are persisted; never waveforms or reports.
public struct ECGAnnotationFileStorage: ECGAnnotationStorage {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("annotations-v1.json") }

    private struct Document: Codable {
        let schemaVersion: Int
        let records: [UUID: ECGAnnotation]
    }

    public init(directory: URL) { self.directory = directory }

    public func load() throws -> [UUID: ECGAnnotation] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return [:]
        }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1 else { throw StorageError.unsupportedSchema }
        return document.records.mapValues(\.normalized)
    }

    public func save(_ annotations: [UUID: ECGAnnotation]) throws {
        let data = try JSONEncoder().encode(Document(schemaVersion: 1, records: annotations))
        try ECGProtectedFile.write(data, to: fileURL, in: directory)
    }

    public func clear() throws {
        try ECGProtectedFile.remove(fileURL)
    }

    private enum StorageError: Error { case unsupportedSchema }
}

/// Shared write path for the app's local health-derived files: complete file protection on iOS and a
/// directory excluded from backup before any sensitive bytes are written.
enum ECGProtectedFile {
    static func write(_ data: Data, to fileURL: URL, in directory: URL) throws {
        var attributes: [FileAttributeKey: Any] = [:]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: attributes)
        // Protect the enclosing directory before any sensitive bytes are written.
        var protectedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedDirectory.setResourceValues(values)
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }

    static func remove(_ fileURL: URL) throws {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return
        }
    }
}

@MainActor
@Observable
public final class ECGAnnotationStore {
    public private(set) var annotations: [UUID: ECGAnnotation] = [:]
    public private(set) var hasLoadFailure = false
    public private(set) var hasSaveFailure = false
    public var exampleAnnotation = ECGAnnotation()
    private let storage: any ECGAnnotationStorage

    public init(storage: any ECGAnnotationStorage) {
        self.storage = storage
        reload()
    }

    public convenience init() {
        let root = URL.applicationSupportDirectory.appendingPathComponent("WatchBeatAnnotations", isDirectory: true)
        self.init(storage: ECGAnnotationFileStorage(directory: root))
    }

    public func annotation(for id: UUID) -> ECGAnnotation { annotations[id] ?? ECGAnnotation() }

    public func reload() {
        do {
            annotations = try storage.load()
            hasLoadFailure = false
            hasSaveFailure = false
        } catch {
            // Never turn a failed read into an empty file on the next save.
            hasLoadFailure = true
        }
    }

    @discardableResult
    public func save(_ annotation: ECGAnnotation, for id: UUID) -> Bool {
        guard !hasLoadFailure else { return false }
        var updated = annotations
        let clean = annotation.normalized
        updated[id] = clean.isEmpty ? nil : clean
        do {
            try storage.save(updated)
            annotations = updated
            hasSaveFailure = false
            return true
        } catch {
            hasSaveFailure = true
            return false
        }
    }

    @discardableResult
    public func clear() -> Bool {
        do {
            try storage.clear()
            annotations = [:]
            exampleAnnotation = ECGAnnotation()
            hasLoadFailure = false
            hasSaveFailure = false
            return true
        } catch {
            hasSaveFailure = true
            return false
        }
    }
}
