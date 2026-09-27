// No `import Foundation` here: this Command Line Tools install ships a broken `_Testing_Foundation`
// cross-import overlay, so a file importing both Testing and Foundation fails to compile.
// `HealthKit` already re-exports the Foundation types used below.
import ECGCore
import HealthKit
import Testing
import WatchBeatHealthKit
import WatchBeatModels

/// Mapper boundary tests. `HKElectrocardiogram` itself cannot be constructed in tests, so the
/// mapper's voltage seam (`ECGVoltageSample`, built from a real `HKQuantity`) is exercised directly.
@Suite struct ECGHealthKitMapperTests {

    @Test func convertsLeadIVoltageToMillivolts() throws {
        let quantity = HKQuantity(unit: HKUnit.volt(), doubleValue: 0.25)
        let millivolts = try #require(ECGHealthKitMapper.millivolts(from: quantity))
        #expect(abs(millivolts - 250.0) < 1e-9)
    }

    @Test func absentVoltageStaysMissingInsteadOfBecomingZero() {
        #expect(ECGHealthKitMapper.millivolts(from: nil) == nil)
    }

    @Test func unitIncompatibleVoltageStaysMissing() {
        let quantity = HKQuantity(unit: HKUnit.count(), doubleValue: 3)
        #expect(ECGHealthKitMapper.millivolts(from: quantity) == nil)
    }

    @Test func preservesMeasurementOrderWithoutSorting() {
        let samples = [
            ECGVoltageSample(timeSinceSampleStart: 0.004, quantity: volts(0.001)),
            ECGVoltageSample(timeSinceSampleStart: 0.000, quantity: volts(0.002)),
            ECGVoltageSample(timeSinceSampleStart: 0.002, quantity: volts(0.003))
        ]

        let signal = ECGHealthKitMapper.signal(
            from: samples,
            declaredMeasurementCount: 3,
            declaredSamplingRateHz: nil
        )

        #expect(signal.timeSeconds == [0.004, 0.000, 0.002])
        #expect(signal.voltageMillivolts == [1.0, 2.0, 3.0])
    }

    @Test func keepsMissingLeadVoltagePosition() throws {
        let samples = [
            ECGVoltageSample(timeSinceSampleStart: 0.0, quantity: volts(0.001)),
            ECGVoltageSample(timeSinceSampleStart: 0.002, quantity: nil),
            ECGVoltageSample(timeSinceSampleStart: 0.004, quantity: volts(0.003))
        ]

        let signal = ECGHealthKitMapper.signal(
            from: samples,
            declaredMeasurementCount: 3,
            declaredSamplingRateHz: nil
        )
        let report = try ECGSignalInspector.inspect(signal)

        #expect(signal.voltageMillivolts.count == 3)
        #expect(signal.voltageMillivolts[1] == nil)
        #expect(report.missingVoltageIndices == [1])
        #expect(report.sampleCount == 3)
    }

    @Test func reportsDeclaredCountMismatch() {
        let samples = [
            ECGVoltageSample(timeSinceSampleStart: 0.0, quantity: volts(0.001)),
            ECGVoltageSample(timeSinceSampleStart: 0.002, quantity: volts(0.001))
        ]

        let issues = ECGHealthKitMapper.completenessIssues(
            measurementCount: samples.count,
            declaredMeasurementCount: 5
        )

        #expect(issues == [.declaredCountMismatch])
    }

    @Test func reportsEmptyMeasurementSequence() {
        let issues = ECGHealthKitMapper.completenessIssues(
            measurementCount: 0,
            declaredMeasurementCount: 0
        )
        #expect(issues == [.noMeasurements])
    }

    @Test func declaredSamplingRateIsPassedThroughUnchanged() {
        let signal = ECGHealthKitMapper.signal(
            from: [ECGVoltageSample(timeSinceSampleStart: 0.0, quantity: volts(0.001))],
            declaredMeasurementCount: 1,
            declaredSamplingRateHz: 512
        )
        #expect(signal.nominalSamplingRateHz == 512)
    }

    @Test func infersSamplingRateWhenRecordDeclaresNone() throws {
        let samples = (0..<6).map { index in
            ECGVoltageSample(timeSinceSampleStart: Double(index) * 0.002, quantity: volts(0.001))
        }

        let signal = ECGHealthKitMapper.signal(
            from: samples,
            declaredMeasurementCount: 6,
            declaredSamplingRateHz: nil
        )
        let report = try ECGSignalInspector.inspect(signal)

        #expect(signal.nominalSamplingRateHz == nil)
        let inferredRate = try #require(report.inferredSamplingRateHz)
        #expect(abs(inferredRate - 500.0) < 1e-9)
    }

    private func volts(_ value: Double) -> HKQuantity {
        HKQuantity(unit: HKUnit.volt(), doubleValue: value)
    }
}
