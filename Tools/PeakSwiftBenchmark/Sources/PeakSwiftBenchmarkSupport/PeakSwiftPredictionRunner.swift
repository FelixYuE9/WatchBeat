import CryptoKit
import Foundation
import PeakSwift

public enum PeakSwiftPredictionRunner {
    private static let peakSwiftVersion = "1.0.0"
    private static let peakSwiftRevision = "18fe5e7c674f915c3666e0414c7f2ac39b241bb9"
    private static let surgeRevision = "6e4a47e63da8801afe6188cf039e9f04eb577721"
    private static let buildConfiguration: String = {
        #if PEAKSWIFT_BENCHMARK_RELEASE
        return "release"
        #elseif PEAKSWIFT_BENCHMARK_DEBUG
        return "debug"
        #else
        return "unknown"
        #endif
    }()

    public static func run(options: BenchmarkOptions) throws {
        let manifestData = try Data(contentsOf: options.manifestURL)
        let manifest = try JSONDecoder().decode(ManifestDocument.self, from: manifestData)
        guard manifest.schemaVersion == 1 else {
            throw BenchmarkToolError.invalidManifest("schemaVersion must equal 1")
        }
        guard manifest.windowDurationSeconds == 30.0 else {
            throw BenchmarkToolError.invalidManifest("windowDurationSeconds must equal 30")
        }
        let selectedWindows = manifest.windows.filter { $0.split == options.stage }
        guard !selectedWindows.isEmpty else {
            throw BenchmarkToolError.invalidManifest(
                "split \(options.stage.rawValue) contains no windows"
            )
        }

        let manifestHash = sha256Hex(manifestData)
        let configuration = DetectorConfiguration(
            adapterSchemaVersion: 1,
            algorithm: options.algorithm,
            buildConfiguration: buildConfiguration,
            inputUnit: "physical-millivolts-from-wfdb-gain-and-baseline-v1",
            manifestSHA256: manifestHash,
            peakIndexPolicy: "strict-upstream-window-local-indices-no-refinement-v1",
            peakSwiftRevision: peakSwiftRevision,
            peakSwiftVersion: peakSwiftVersion,
            surgeRevision: surgeRevision,
            windowPolicy: "independent-complete-30-second-windows-v1"
        )
        let configHash = try sha256Hex(sortedJSONData(configuration))
        let detector = QRSDetector()
        var predictions: [WindowPrediction] = []
        predictions.reserveCapacity(selectedWindows.count)
        var cachedRecordId: String?
        var cachedChannelIndex: Int?
        var cachedHeader: WFDBRecordHeader?
        var cachedMillivolts: [Double] = []

        for (index, window) in selectedWindows.enumerated() {
            try validate(window: window)
            if cachedRecordId != window.recordId || cachedChannelIndex != window.channelIndex {
                let decoded = try WFDB212Reader.readChannel(
                    datasetDirectoryURL: options.datasetDirectoryURL,
                    recordId: window.recordId,
                    channelIndex: window.channelIndex
                )
                cachedRecordId = window.recordId
                cachedChannelIndex = window.channelIndex
                cachedHeader = decoded.header
                cachedMillivolts = decoded.millivolts
                writeProgress(
                    "[\(index + 1)/\(selectedWindows.count)] record \(window.recordId), " +
                    "channel \(window.channelIndex), algorithm \(options.algorithm.rawValue)"
                )
            }
            guard let header = cachedHeader,
                  abs(header.samplingFrequencyHz - window.samplingFrequencyHz) < 1e-9,
                  window.endSampleExclusive <= cachedMillivolts.count else {
                throw BenchmarkToolError.invalidManifest(
                    "window \(window.id) does not match record header/data"
                )
            }
            let values = Array(
                cachedMillivolts[window.startSample..<window.endSampleExclusive]
            )
            let result = detector.detectPeaks(
                electrocardiogram: Electrocardiogram(
                    ecg: values,
                    samplingRate: window.samplingFrequencyHz
                ),
                algorithm: options.algorithm.upstreamValue
            )
            let globalPeaks = try globalPeakIndices(
                result.rPeaks,
                window: window,
                localSampleCount: values.count
            )
            predictions.append(
                WindowPrediction(id: window.id, detectedPeakSamples: globalPeaks)
            )
        }

        let document = PredictionDocument(
            schemaVersion: 1,
            claimStatus: "research-only-unvalidated",
            detector: DetectorIdentity(
                name: "PeakSwift/\(options.algorithm.rawValue)",
                version: "v\(peakSwiftVersion)@\(peakSwiftRevision)",
                configHash: configHash
            ),
            configuration: configuration,
            evaluatedSplit: options.stage,
            windows: predictions
        )
        var output = try sortedJSONData(document, prettyPrinted: true)
        output.append(0x0A)
        try FileManager.default.createDirectory(
            at: options.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try output.write(to: options.outputURL, options: [.atomic])
        writeProgress(
            "Wrote \(predictions.count) \(options.stage.rawValue) windows to " +
            options.outputURL.path
        )
    }

    private static func validate(window: ManifestWindow) throws {
        let recordBytes = Array(window.recordId.utf8)
        guard !window.id.isEmpty,
              recordBytes.count == 3,
              recordBytes.allSatisfy({ (0x30...0x39).contains($0) }),
              window.channelIndex >= 0,
              window.samplingFrequencyHz.isFinite,
              window.samplingFrequencyHz > 0,
              window.startSample >= 0,
              window.endSampleExclusive > window.startSample,
              abs(
                  Double(window.endSampleExclusive - window.startSample)
                    / window.samplingFrequencyHz - 30.0
              ) < 1e-9 else {
            throw BenchmarkToolError.invalidManifest("invalid 30-second window \(window.id)")
        }
    }

    private static func globalPeakIndices(
        _ upstreamPeaks: [UInt],
        window: ManifestWindow,
        localSampleCount: Int
    ) throws -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(upstreamPeaks.count)
        var previous: Int?
        for rawPeak in upstreamPeaks {
            guard let localPeak = Int(exactly: rawPeak),
                  localPeak >= 0,
                  localPeak < localSampleCount else {
                throw BenchmarkToolError.invalidDetectorOutput(
                    "algorithm returned an out-of-window peak for \(window.id)"
                )
            }
            if let previous, localPeak <= previous {
                throw BenchmarkToolError.invalidDetectorOutput(
                    "algorithm returned duplicate or unsorted peaks for \(window.id)"
                )
            }
            result.append(window.startSample + localPeak)
            previous = localPeak
        }
        return result
    }

    private static func sortedJSONData<T: Encodable>(
        _ value: T,
        prettyPrinted: Bool = false
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func writeProgress(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
