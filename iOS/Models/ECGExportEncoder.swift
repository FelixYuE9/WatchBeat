import ECGCore
import Foundation

public enum ECGExportEncodingError: Error, Equatable, Sendable {
    case mismatchedSampleCounts(timeCount: Int, voltageCount: Int)
}

/// Lossless, local encoders for user-triggered export. No HealthKit identifier is included.
public enum ECGExportEncoder {
    public static let rawCSVFileName = "watchbeat-ecg-raw.csv"
    public static let metadataJSONFileName = "watchbeat-ecg-metadata.json"
    public static let analysisJSONFileName = "watchbeat-ecg-analysis.json"
    public static let syntheticRawCSVFileName = "watchbeat-synthetic-example-raw.csv"
    public static let syntheticMetadataJSONFileName = "watchbeat-synthetic-example-metadata.json"
    public static let syntheticAnalysisJSONFileName = "watchbeat-synthetic-example-analysis.json"

    /// Preserves source order, real timestamps and missing voltages. A missing voltage is an empty
    /// field, matching `Tools/Validation/validate_raw_ecg_csv.py`.
    public static func rawCSV(for measurement: ECGMeasurement) throws -> Data {
        let signal = measurement.signal
        guard signal.timeSeconds.count == signal.voltageMillivolts.count else {
            throw ECGExportEncodingError.mismatchedSampleCounts(
                timeCount: signal.timeSeconds.count,
                voltageCount: signal.voltageMillivolts.count
            )
        }

        var text = "time_s,voltage_mV\n"
        for index in signal.timeSeconds.indices {
            text += String(signal.timeSeconds[index])
            text += ","
            if let voltage = signal.voltageMillivolts[index] {
                text += String(voltage)
            }
            text += "\n"
        }
        return Data(text.utf8)
    }

    public static func metadataJSON(for measurement: ECGMeasurement) throws -> Data {
        let payload = MetadataPayload(measurement: measurement)
        return try sortedJSON(payload)
    }

    /// Stable model-output JSON. The payload contains no HealthKit identifier or acquisition date.
    public static func analysisJSON(for measurement: ECGMeasurement) throws -> Data {
        try sortedJSON(measurement.analysis)
    }

    private static func sortedJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

private struct MetadataPayload: Encodable {
    let format = "watchbeat.ecg.metadata"
    let schemaVersion = 1
    let dataSource: String
    let units = Units()
    let record: Record
    let measurement: Measurement

    init(measurement: ECGMeasurement) {
        dataSource = measurement.source.rawValue
        record = Record(record: measurement.record, source: measurement.source)
        self.measurement = Measurement(measurement: measurement)
    }

    struct Units: Encodable {
        let time = "seconds"
        let voltage = "millivolts"
        let samplingFrequency = "hertz"
        let averageHeartRate = "beats-per-minute"
    }

    struct Record: Encodable {
        let startDate: Date?
        let endDate: Date?
        let durationSeconds: Double
        let classification: String?
        let averageHeartRateBPM: Double?
        let samplingFrequencyHz: Double?
        let declaredMeasurementCount: Int
        let symptomsStatus: String?

        init(record: ECGRecord, source: ECGMeasurementSource) {
            let isHealthKit = source == .healthKit
            startDate = isHealthKit ? record.startDate : nil
            endDate = isHealthKit ? record.endDate : nil
            durationSeconds = record.durationSeconds
            classification = isHealthKit ? record.classification.rawValue : nil
            averageHeartRateBPM = record.averageHeartRateBPM
            samplingFrequencyHz = record.samplingFrequencyHz
            declaredMeasurementCount = record.declaredMeasurementCount
            symptomsStatus = isHealthKit ? record.symptomsStatus.rawValue : nil
        }
    }

    struct Measurement: Encodable {
        let loadedSampleCount: Int
        let issues: [String]
        let missingVoltageIndices: [Int]
        let nonFiniteTimeIndices: [Int]
        let nonFiniteVoltageIndices: [Int]
        let duplicateTimestampIndices: [Int]
        let decreasingTimestampIndices: [Int]
        let medianSamplingIntervalSeconds: Double?
        let inferredSamplingRateHz: Double?
        let samplingIntervalRelativeMAD: Double?

        init(measurement: ECGMeasurement) {
            let integrity = measurement.integrity
            loadedSampleCount = integrity.sampleCount
            issues = measurement.issues.map(\.rawValue)
            missingVoltageIndices = integrity.missingVoltageIndices
            nonFiniteTimeIndices = integrity.nonFiniteTimeIndices
            nonFiniteVoltageIndices = integrity.nonFiniteVoltageIndices
            duplicateTimestampIndices = integrity.duplicateTimestampIndices
            decreasingTimestampIndices = integrity.decreasingTimestampIndices
            medianSamplingIntervalSeconds = integrity.medianSamplingIntervalSeconds
            inferredSamplingRateHz = integrity.inferredSamplingRateHz
            samplingIntervalRelativeMAD = integrity.samplingIntervalRelativeMAD
        }
    }
}
