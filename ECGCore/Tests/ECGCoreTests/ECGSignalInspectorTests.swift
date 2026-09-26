import XCTest
@testable import ECGCore

final class ECGSignalInspectorTests: XCTestCase {
    func testInfersSamplingRateFromMedianPositiveDelta() throws {
        let signal = ECGSignal(
            timeSeconds: [0.000, 0.002, 0.004, 0.006, 0.008],
            voltageMillivolts: [0.01, 0.02, 0.03, 0.02, 0.01],
            nominalSamplingRateHz: nil
        )

        let report = try ECGSignalInspector.inspect(signal)
        let inferredRate = try XCTUnwrap(report.inferredSamplingRateHz)

        XCTAssertEqual(inferredRate, 500.0, accuracy: 0.000_001)
        XCTAssertTrue(report.hasStrictlyIncreasingFiniteTimestamps)
        XCTAssertEqual(report.sampleCount, 5)
    }

    func testPreservesAndReportsMissingVoltagePosition() throws {
        let signal = ECGSignal(
            timeSeconds: [0.0, 0.01, 0.02],
            voltageMillivolts: [0.1, nil, 0.2],
            nominalSamplingRateHz: 100.0
        )

        let report = try ECGSignalInspector.inspect(signal)

        XCTAssertEqual(report.missingVoltageIndices, [1])
        XCTAssertEqual(signal.voltageMillivolts.count, 3)
    }

    func testReportsDuplicateAndDecreasingTimestamps() throws {
        let signal = ECGSignal(
            timeSeconds: [0.0, 0.01, 0.01, 0.005],
            voltageMillivolts: [0.1, 0.2, 0.3, 0.4],
            nominalSamplingRateHz: nil
        )

        let report = try ECGSignalInspector.inspect(signal)

        XCTAssertEqual(report.duplicateTimestampIndices, [2])
        XCTAssertEqual(report.decreasingTimestampIndices, [3])
        XCTAssertFalse(report.hasStrictlyIncreasingFiniteTimestamps)
    }

    func testRejectsMismatchedArrayLengths() {
        let signal = ECGSignal(
            timeSeconds: [0.0, 0.01],
            voltageMillivolts: [0.1],
            nominalSamplingRateHz: nil
        )

        XCTAssertThrowsError(try ECGSignalInspector.inspect(signal)) { error in
            XCTAssertEqual(
                error as? ECGSignalInspectionError,
                .mismatchedSampleCounts(timeCount: 2, voltageCount: 1)
            )
        }
    }

    func testReportsNonFiniteValuesWithoutDroppingSamples() throws {
        let signal = ECGSignal(
            timeSeconds: [0.0, .infinity, 0.02],
            voltageMillivolts: [0.1, .nan, 0.2],
            nominalSamplingRateHz: nil
        )

        let report = try ECGSignalInspector.inspect(signal)

        XCTAssertEqual(report.nonFiniteTimeIndices, [1])
        XCTAssertEqual(report.nonFiniteVoltageIndices, [1])
        XCTAssertEqual(report.sampleCount, 3)
    }
}
