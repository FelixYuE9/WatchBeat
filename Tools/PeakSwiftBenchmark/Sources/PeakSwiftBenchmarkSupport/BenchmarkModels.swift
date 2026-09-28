import Foundation
import PeakSwift

public enum BenchmarkToolError: LocalizedError, Equatable {
    case invalidArgument(String)
    case invalidManifest(String)
    case invalidWFDB(String)
    case invalidDetectorOutput(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArgument(let message):
            return message
        case .invalidManifest(let message):
            return "invalid manifest: \(message)"
        case .invalidWFDB(let message):
            return "invalid WFDB input: \(message)"
        case .invalidDetectorOutput(let message):
            return "invalid detector output: \(message)"
        }
    }
}

public enum BenchmarkStage: String, CaseIterable, Codable, Sendable {
    case development
    case validation
    case heldOutTest = "held-out-test"
}

public enum PeakSwiftAlgorithmName: String, CaseIterable, Codable, Sendable {
    case christov
    case nabian2018
    case hamilton
    case twoAverage = "two-average"
    case neurokit
    case panTompkins = "pan-tompkins"
    case unsw
    case engzee
    case kalidas

    var upstreamValue: Algorithms {
        switch self {
        case .christov: return .christov
        case .nabian2018: return .nabian2018
        case .hamilton: return .hamilton
        case .twoAverage: return .twoAverage
        case .neurokit: return .neurokit
        case .panTompkins: return .panTompkins
        case .unsw: return .unsw
        case .engzee: return .engzee
        case .kalidas: return .kalidas
        }
    }
}

public struct BenchmarkOptions: Equatable, Sendable {
    public let manifestURL: URL
    public let datasetDirectoryURL: URL
    public let outputURL: URL
    public let algorithm: PeakSwiftAlgorithmName
    public let stage: BenchmarkStage
    public let allowsHeldOutTest: Bool

    public static let usage = """
    Usage:
      PeakSwiftBenchmark --manifest <manifest.json> --dataset-dir <mitdb-dir>
        --output <predictions.json> --algorithm <name> --split <stage>
        [--allow-held-out-test]

    Algorithms: \(PeakSwiftAlgorithmName.allCases.map(\.rawValue).joined(separator: ", "))
    Stages: development, validation, held-out-test

    held-out-test is rejected unless --allow-held-out-test is supplied intentionally.
    """

    public static func parse(_ arguments: [String]) throws -> BenchmarkOptions {
        var values: [String: String] = [:]
        var allowsHeldOutTest = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--allow-held-out-test" {
                guard !allowsHeldOutTest else {
                    throw BenchmarkToolError.invalidArgument(
                        "--allow-held-out-test must not be repeated"
                    )
                }
                allowsHeldOutTest = true
                index += 1
                continue
            }
            guard ["--manifest", "--dataset-dir", "--output", "--algorithm", "--split"]
                .contains(argument) else {
                throw BenchmarkToolError.invalidArgument("unknown argument: \(argument)")
            }
            guard values[argument] == nil else {
                throw BenchmarkToolError.invalidArgument("duplicate argument: \(argument)")
            }
            guard index + 1 < arguments.count else {
                throw BenchmarkToolError.invalidArgument("missing value for \(argument)")
            }
            values[argument] = arguments[index + 1]
            index += 2
        }

        func require(_ name: String) throws -> String {
            guard let value = values[name], !value.isEmpty else {
                throw BenchmarkToolError.invalidArgument("missing required argument: \(name)")
            }
            return value
        }

        let algorithmValue = try require("--algorithm")
        guard let algorithm = PeakSwiftAlgorithmName(rawValue: algorithmValue) else {
            throw BenchmarkToolError.invalidArgument("unsupported algorithm: \(algorithmValue)")
        }
        let stageValue = try require("--split")
        guard let stage = BenchmarkStage(rawValue: stageValue) else {
            throw BenchmarkToolError.invalidArgument("unsupported benchmark split: \(stageValue)")
        }
        if stage == .heldOutTest && !allowsHeldOutTest {
            throw BenchmarkToolError.invalidArgument(
                "held-out-test is locked; add --allow-held-out-test only after detector selection is frozen"
            )
        }

        let currentDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        func fileURL(_ value: String) -> URL {
            URL(fileURLWithPath: value, relativeTo: currentDirectory).standardizedFileURL
        }

        let manifestURL = fileURL(try require("--manifest"))
        let datasetDirectoryURL = fileURL(try require("--dataset-dir"))
        let outputURL = fileURL(try require("--output"))
        guard outputURL != manifestURL else {
            throw BenchmarkToolError.invalidArgument("output must not overwrite the manifest")
        }
        let datasetPrefix = datasetDirectoryURL.path.hasSuffix("/")
            ? datasetDirectoryURL.path
            : datasetDirectoryURL.path + "/"
        guard !outputURL.path.hasPrefix(datasetPrefix) else {
            throw BenchmarkToolError.invalidArgument(
                "output must not be written inside the checksum-verified dataset directory"
            )
        }

        return BenchmarkOptions(
            manifestURL: manifestURL,
            datasetDirectoryURL: datasetDirectoryURL,
            outputURL: outputURL,
            algorithm: algorithm,
            stage: stage,
            allowsHeldOutTest: allowsHeldOutTest
        )
    }
}

struct ManifestDocument: Decodable {
    let schemaVersion: Int
    let windowDurationSeconds: Double
    let windows: [ManifestWindow]
}

struct ManifestWindow: Decodable {
    let id: String
    let recordId: String
    let split: BenchmarkStage
    let channelIndex: Int
    let samplingFrequencyHz: Double
    let startSample: Int
    let endSampleExclusive: Int
}

struct DetectorConfiguration: Codable, Equatable {
    let adapterSchemaVersion: Int
    let algorithm: PeakSwiftAlgorithmName
    let buildConfiguration: String
    let inputUnit: String
    let manifestSHA256: String
    let peakIndexPolicy: String
    let peakSwiftRevision: String
    let peakSwiftVersion: String
    let surgeRevision: String
    let windowPolicy: String
}

struct DetectorIdentity: Encodable {
    let name: String
    let version: String
    let configHash: String
}

struct WindowPrediction: Encodable {
    let id: String
    let detectedPeakSamples: [Int]
}

struct PredictionDocument: Encodable {
    let schemaVersion: Int
    let claimStatus: String
    let detector: DetectorIdentity
    let configuration: DetectorConfiguration
    let evaluatedSplit: BenchmarkStage
    let windows: [WindowPrediction]
}
