import ECGCore
import Foundation

/// Creates the educational ECG bundled with every build. It produces the exact same canonical
/// `ECGSignal` consumed by the HealthKit path and is analyzed by the exact same on-device model.
/// The signal is analytic, deterministic and contains no human health data; it is not validation.
///
/// The rhythm is regular at 70 BPM except for one early narrow (PAC-like) beat and one early wide
/// (PVC-like) beat, so the tutorial shows what a flagged candidate looks like. Their positions are
/// never passed to the analyzer or the UI; any marker on screen comes from the model report.
public enum ECGExampleFactory {
    public static let samplingFrequencyHz = 500.0
    public static let durationSeconds = 30.0
    public static let averageHeartRateBPM = 70.0
    public static let beatPeriodSeconds = 60.0 / averageHeartRateBPM

    private static let firstRPeakSeconds = 0.347
    private static let pacLikeBeatNumber = 11
    private static let pvcLikeBeatNumber = 25
    private static let prematureCouplingRatio = 0.62

    public static func makeMeasurement() throws -> ECGMeasurement {
        let sampleCount = Int(samplingFrequencyHz * durationSeconds)
        let times = (0..<sampleCount).map { Double($0) / samplingFrequencyHz }
        var voltages: [Double] = times.map { 0.025 * sin(2 * Double.pi * 0.28 * $0) }

        // Each beat only affects samples within ±0.7 s of its R peak.
        let reachSamples = Int(0.7 * samplingFrequencyHz)
        for beat in beats() {
            let center = Int((beat.rPeakSeconds * samplingFrequencyHz).rounded())
            let lower = max(0, center - reachSamples)
            let upper = min(sampleCount - 1, center + reachSamples)
            guard lower <= upper else { continue }
            for index in lower...upper {
                voltages[index] += beatVoltage(
                    offsetSeconds: times[index] - beat.rPeakSeconds,
                    isVentricular: beat.isVentricular
                )
            }
        }

        let signal = ECGSignal(
            timeSeconds: times,
            voltageMillivolts: voltages.map { Optional.some($0) },
            nominalSamplingRateHz: samplingFrequencyHz
        )
        let startDate = Date(timeIntervalSince1970: 946_684_800)
        let record = ECGRecord(
            id: UUID(uuid: (
                0x57, 0x42, 0x45, 0x41, 0x54, 0x00, 0x40, 0x00,
                0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
            )),
            startDate: startDate,
            endDate: startDate.addingTimeInterval(durationSeconds),
            classification: .notSet,
            averageHeartRateBPM: averageHeartRateBPM,
            samplingFrequencyHz: samplingFrequencyHz,
            declaredMeasurementCount: sampleCount,
            symptomsStatus: .notSet
        )
        return ECGMeasurement(
            record: record,
            signal: signal,
            integrity: try ECGSignalInspector.inspect(signal),
            issues: [],
            source: .builtInSyntheticExample
        )
    }

    private struct SyntheticBeat {
        let rPeakSeconds: Double
        let isVentricular: Bool
    }

    private static func beats() -> [SyntheticBeat] {
        var beats: [SyntheticBeat] = []
        var time = firstRPeakSeconds
        var number = 0
        while time < durationSeconds + 1 {
            let isPAC = number == pacLikeBeatNumber
            let isPVC = number == pvcLikeBeatNumber
            beats.append(SyntheticBeat(rPeakSeconds: time, isVentricular: isPVC))

            let nextIsPremature = number + 1 == pacLikeBeatNumber || number + 1 == pvcLikeBeatNumber
            if nextIsPremature {
                time += prematureCouplingRatio * beatPeriodSeconds
            } else if isPAC {
                // Non-compensatory pause.
                time += 1.05 * beatPeriodSeconds
            } else if isPVC {
                // Fully compensatory pause.
                time += (2 - prematureCouplingRatio) * beatPeriodSeconds
            } else {
                time += beatPeriodSeconds
            }
            number += 1
        }
        return beats
    }

    private static func beatVoltage(offsetSeconds dt: Double, isVentricular: Bool) -> Double {
        if isVentricular {
            // No P wave, wide QRS and discordant T wave.
            return 1.25 * gaussian(dt, center: 0, width: 0.028)
                - 0.55 * gaussian(dt, center: 0.07, width: 0.03)
                - 0.30 * gaussian(dt, center: 0.30, width: 0.07)
        }
        return 0.10 * gaussian(dt, center: -0.193, width: 0.030)
            - 0.16 * gaussian(dt, center: -0.0214, width: 0.0103)
            + 1.05 * gaussian(dt, center: 0, width: 0.00857)
            - 0.28 * gaussian(dt, center: 0.0257, width: 0.012)
            + 0.24 * gaussian(dt, center: 0.235, width: 0.060)
    }

    private static func gaussian(_ value: Double, center: Double, width: Double) -> Double {
        let standardized = (value - center) / width
        return exp(-0.5 * standardized * standardized)
    }
}
