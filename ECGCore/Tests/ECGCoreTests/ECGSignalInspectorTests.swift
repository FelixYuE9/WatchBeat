import Testing
@testable import ECGCore

@Suite struct ECGSignalInspectorTests {
    @Test func infersSamplingRateFromMedianPositiveDelta() throws {
        let signal = ECGSignal(
            timeSeconds: [0.000, 0.002, 0.004, 0.006, 0.008],
            voltageMillivolts: [0.01, 0.02, 0.03, 0.02, 0.01],
            nominalSamplingRateHz: nil
        )

        let report = try ECGSignalInspector.inspect(signal)
        let inferredRate = try #require(report.inferredSamplingRateHz)

        #expect(abs(inferredRate - 500.0) < 0.000_001)
        #expect(report.hasStrictlyIncreasingFiniteTimestamps)
        #expect(report.sampleCount == 5)
    }

    @Test func preservesAndReportsMissingVoltagePosition() throws {
        let signal = ECGSignal(
            timeSeconds: [0.0, 0.01, 0.02],
            voltageMillivolts: [0.1, nil, 0.2],
            nominalSamplingRateHz: 100.0
        )

        let report = try ECGSignalInspector.inspect(signal)

        #expect(report.missingVoltageIndices == [1])
        #expect(signal.voltageMillivolts.count == 3)
    }

    @Test func reportsDuplicateAndDecreasingTimestamps() throws {
        let signal = ECGSignal(
            timeSeconds: [0.0, 0.01, 0.01, 0.005],
            voltageMillivolts: [0.1, 0.2, 0.3, 0.4],
            nominalSamplingRateHz: nil
        )

        let report = try ECGSignalInspector.inspect(signal)

        #expect(report.duplicateTimestampIndices == [2])
        #expect(report.decreasingTimestampIndices == [3])
        #expect(report.hasStrictlyIncreasingFiniteTimestamps == false)
    }

    @Test func rejectsMismatchedArrayLengths() {
        let signal = ECGSignal(
            timeSeconds: [0.0, 0.01],
            voltageMillivolts: [0.1],
            nominalSamplingRateHz: nil
        )

        #expect(
            throws: ECGSignalInspectionError.mismatchedSampleCounts(timeCount: 2, voltageCount: 1)
        ) {
            try ECGSignalInspector.inspect(signal)
        }
    }

    @Test func reportsNonFiniteValuesWithoutDroppingSamples() throws {
        let signal = ECGSignal(
            timeSeconds: [0.0, .infinity, 0.02],
            voltageMillivolts: [0.1, .nan, 0.2],
            nominalSamplingRateHz: nil
        )

        let report = try ECGSignalInspector.inspect(signal)

        #expect(report.nonFiniteTimeIndices == [1])
        #expect(report.nonFiniteVoltageIndices == [1])
        #expect(report.sampleCount == 3)
    }
}
