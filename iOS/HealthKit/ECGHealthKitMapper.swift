import ECGCore
import Foundation
import HealthKit
import WatchBeatModels

/// Converts HealthKit ECG objects into platform-neutral values.
///
/// Guarantees enforced here:
/// - `.appleWatchSimilarToLeadI` voltage is converted to mV exactly once, at this boundary.
/// - Measurement order and timestamps are preserved; nothing is sorted, dropped, or interpolated.
/// - A missing or unit-incompatible quantity becomes `nil`, never a fabricated value.
/// - The declared measurement count is carried through so a mismatch can be reported.
public enum ECGHealthKitMapper {
    public static let leadI = HKElectrocardiogram.Lead.appleWatchSimilarToLeadI

    private static let voltUnit = HKUnit.volt()
    private static let millivoltUnit = HKUnit(from: "mV")
    private static let hertzUnit = HKUnit.hertz()
    private static let beatsPerMinuteUnit = HKUnit(from: "count/min")

    // MARK: - Metadata

    public static func record(from sample: HKElectrocardiogram) -> ECGRecord {
        ECGRecord(
            id: sample.uuid,
            startDate: sample.startDate,
            endDate: sample.endDate,
            classification: classification(from: sample.classification),
            averageHeartRateBPM: sample.averageHeartRate.flatMap { doubleValue($0, unit: beatsPerMinuteUnit) },
            samplingFrequencyHz: sample.samplingFrequency.flatMap { doubleValue($0, unit: hertzUnit) },
            declaredMeasurementCount: sample.numberOfVoltageMeasurements,
            symptomsStatus: symptomsStatus(from: sample.symptomsStatus)
        )
    }

    // MARK: - Voltage

    public static func voltageSample(from measurement: HKElectrocardiogram.VoltageMeasurement) -> ECGVoltageSample {
        ECGVoltageSample(
            timeSinceSampleStart: measurement.timeSinceSampleStart,
            quantity: measurement.quantity(for: leadI)
        )
    }

    /// Converts volts to millivolts. Returns `nil` when the quantity is absent or not voltage
    /// compatible, so a missing lead value stays missing instead of becoming zero.
    public static func millivolts(from quantity: HKQuantity?) -> Double? {
        guard let quantity, quantity.is(compatibleWith: voltUnit) else { return nil }
        return quantity.doubleValue(for: millivoltUnit)
    }

    /// Builds the canonical `watchbeat.ecg.signal.v1` model input in arrival order.
    public static func signal(
        from samples: [ECGVoltageSample],
        declaredMeasurementCount: Int?,
        declaredSamplingRateHz: Double?
    ) -> ECGSignal {
        var timeSeconds: [Double] = []
        var voltageMillivolts: [Double?] = []
        timeSeconds.reserveCapacity(samples.count)
        voltageMillivolts.reserveCapacity(samples.count)

        for sample in samples {
            timeSeconds.append(sample.timeSinceSampleStart)
            voltageMillivolts.append(millivolts(from: sample.quantity))
        }

        return ECGSignal(
            timeSeconds: timeSeconds,
            voltageMillivolts: voltageMillivolts,
            nominalSamplingRateHz: declaredSamplingRateHz
        )
    }

    /// Completeness facts that do not require the ECGCore inspector.
    public static func completenessIssues(
        measurementCount: Int,
        declaredMeasurementCount: Int
    ) -> [ECGMeasurementIssue] {
        guard measurementCount > 0 else { return [.noMeasurements] }
        guard measurementCount == declaredMeasurementCount else { return [.declaredCountMismatch] }
        return []
    }

    // MARK: - Helpers

    private static func doubleValue(_ quantity: HKQuantity, unit: HKUnit) -> Double? {
        guard quantity.is(compatibleWith: unit) else { return nil }
        return quantity.doubleValue(for: unit)
    }

    private static func classification(
        from value: HKElectrocardiogram.Classification
    ) -> ECGAppleClassification {
        switch value {
        case .notSet: return .notSet
        case .sinusRhythm: return .sinusRhythm
        case .atrialFibrillation: return .atrialFibrillation
        case .inconclusiveLowHeartRate: return .inconclusiveLowHeartRate
        case .inconclusiveHighHeartRate: return .inconclusiveHighHeartRate
        case .inconclusivePoorReading: return .inconclusivePoorReading
        case .inconclusiveOther: return .inconclusiveOther
        case .unrecognized: return .unrecognized
        @unknown default: return .unrecognized
        }
    }

    private static func symptomsStatus(
        from value: HKElectrocardiogram.SymptomsStatus
    ) -> ECGSymptomsStatus {
        switch value {
        case .notSet: return .notSet
        case .none: return .none
        case .present: return .present
        @unknown default: return .notSet
        }
    }
}
