import Foundation
import XCTest
@testable import PeakSwiftBenchmarkSupport

final class WFDB212ReaderTests: XCTestCase {
    func testDecodesBothMITFormat212ChannelsToMillivolts() throws {
        // First samples from MIT-BIH record 100: channel 0 ADC 995, channel 1 ADC 1011.
        let data = Data([0xE3, 0x33, 0xF3])

        let channel0 = try WFDB212Reader.decodeChannel(
            data: data,
            sampleCount: 1,
            channelIndex: 0,
            gainADCUnitsPerMillivolt: 200,
            baselineADCUnits: 1024
        )
        let channel1 = try WFDB212Reader.decodeChannel(
            data: data,
            sampleCount: 1,
            channelIndex: 1,
            gainADCUnitsPerMillivolt: 200,
            baselineADCUnits: 1024
        )

        XCTAssertEqual(channel0, [-0.145])
        XCTAssertEqual(channel1, [-0.065])
    }

    func testHeaderParserPreservesRecord114ReversedLeadOrder() throws {
        let header = try WFDB212Reader.parseHeader(
            """
            114 2 360 650000
            114.dat 212 200 11 1024 1015 -11371 0 V5
            114.dat 212 200 11 1024 1027 -13230 0 MLII
            # comment
            """,
            expectedRecordId: "114"
        )

        XCTAssertEqual(header.signals.map(\.name), ["V5", "MLII"])
        XCTAssertEqual(header.sampleCount, 650_000)
        XCTAssertEqual(header.samplingFrequencyHz, 360)
    }

    func testHeaderParserRejectsUnsafeDataFilename() {
        XCTAssertThrowsError(
            try WFDB212Reader.parseHeader(
                """
                100 2 360 1
                ../100.dat 212 200 11 1024 995 0 0 MLII
                ../100.dat 212 200 11 1024 1011 0 0 V5
                """,
                expectedRecordId: "100"
            )
        )
    }

    func testHeldOutStageRequiresIntentionalUnlock() {
        XCTAssertThrowsError(
            try BenchmarkOptions.parse([
                "--manifest", "manifest.json",
                "--dataset-dir", "data",
                "--output", "predictions.json",
                "--algorithm", "neurokit",
                "--split", "held-out-test"
            ])
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("held-out-test is locked"))
        }
    }
}
