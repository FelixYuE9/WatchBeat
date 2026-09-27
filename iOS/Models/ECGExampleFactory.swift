import ECGCore
import Foundation

/// Creates the educational ECG bundled with every build. The signal is analytic, deterministic
/// and contains no human health data. It is for learning the UI, not algorithm validation.
public enum ECGExampleFactory {
    public static let samplingFrequencyHz = 500.0
    public static let durationSeconds = 30.0

    public static func makeMeasurement() throws -> ECGMeasurement {
        let sampleCount = Int(samplingFrequencyHz * durationSeconds)
        var times: [Double] = []
        var voltages: [Double?] = []
        times.reserveCapacity(sampleCount)
        voltages.reserveCapacity(sampleCount)

        for index in 0..<sampleCount {
            let time = Double(index) / samplingFrequencyHz
            times.append(time)
            voltages.append(syntheticVoltageMillivolts(at: time))
        }

        let signal = ECGSignal(
            timeSeconds: times,
            voltageMillivolts: voltages,
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
            averageHeartRateBPM: 70,
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

    private static func syntheticVoltageMillivolts(at time: Double) -> Double {
        let beatPeriod = 60.0 / 70.0
        let phase = time.truncatingRemainder(dividingBy: beatPeriod) / beatPeriod
        let baseline = 0.025 * sin(2 * .pi * 0.28 * time)
        let pWave = 0.10 * gaussian(phase, center: 0.18, width: 0.035)
        let qWave = -0.16 * gaussian(phase, center: 0.38, width: 0.012)
        let rWave = 1.05 * gaussian(phase, center: 0.405, width: 0.010)
        let sWave = -0.28 * gaussian(phase, center: 0.435, width: 0.014)
        let tWave = 0.24 * gaussian(phase, center: 0.68, width: 0.070)
        return baseline + pWave + qWave + rWave + sWave + tWave
    }

    private static func gaussian(_ value: Double, center: Double, width: Double) -> Double {
        let standardized = (value - center) / width
        return exp(-0.5 * standardized * standardized)
    }
}
