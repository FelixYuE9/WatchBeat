import Foundation
import WatchBeatModels

enum ECGExportKind: String, Identifiable {
    case rawCSV
    case metadataJSON
    case analysisJSON

    var id: String { rawValue }
}

struct ECGTemporaryExportFile: Identifiable {
    let id = UUID()
    let fileURL: URL
    let directoryURL: URL
}

enum ECGTemporaryExportWriter {
    static func create(
        kind: ECGExportKind,
        measurement: ECGMeasurement
    ) throws -> ECGTemporaryExportFile {
        let data: Data
        let fileName: String
        switch kind {
        case .rawCSV:
            data = try ECGExportEncoder.rawCSV(for: measurement)
            fileName = measurement.source == .builtInSyntheticExample
                ? ECGExportEncoder.syntheticRawCSVFileName
                : ECGExportEncoder.rawCSVFileName
        case .metadataJSON:
            data = try ECGExportEncoder.metadataJSON(for: measurement)
            fileName = measurement.source == .builtInSyntheticExample
                ? ECGExportEncoder.syntheticMetadataJSONFileName
                : ECGExportEncoder.metadataJSONFileName
        case .analysisJSON:
            data = try ECGExportEncoder.analysisJSON(for: measurement)
            fileName = measurement.source == .builtInSyntheticExample
                ? ECGExportEncoder.syntheticAnalysisJSONFileName
                : ECGExportEncoder.analysisJSONFileName
        }

        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("WatchBeatExport-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: false
            )
            let fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
            var options: Data.WritingOptions = .atomic
            #if os(iOS)
            options.insert(.completeFileProtection)
            #endif
            try data.write(to: fileURL, options: options)
            return ECGTemporaryExportFile(fileURL: fileURL, directoryURL: directoryURL)
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw error
        }
    }

    static func remove(_ file: ECGTemporaryExportFile) {
        try? FileManager.default.removeItem(at: file.directoryURL)
    }
}

#if canImport(UIKit)
import SwiftUI
import UIKit

struct ECGShareSheet: UIViewControllerRepresentable {
    let file: ECGTemporaryExportFile

    func makeCoordinator() -> Coordinator {
        Coordinator(file: file)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [file.fileURL],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            context.coordinator.cleanUp()
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

    static func dismantleUIViewController(
        _ controller: UIActivityViewController,
        coordinator: Coordinator
    ) {
        coordinator.cleanUp()
    }

    final class Coordinator {
        private let file: ECGTemporaryExportFile
        private var hasCleanedUp = false

        init(file: ECGTemporaryExportFile) {
            self.file = file
        }

        func cleanUp() {
            guard !hasCleanedUp else { return }
            ECGTemporaryExportWriter.remove(file)
            hasCleanedUp = true
        }
    }
}
#endif
