import XCTest
@testable import ECGCore

final class PublicContractTests: XCTestCase {
    func testBeatClassificationRawValuesRemainExportStable() {
        XCTAssertEqual(BeatClassification.normal.rawValue, "normal")
        XCTAssertEqual(BeatClassification.possiblePAC.rawValue, "possiblePAC")
        XCTAssertEqual(BeatClassification.possiblePVC.rawValue, "possiblePVC")
        XCTAssertEqual(BeatClassification.prematureUncertain.rawValue, "prematureUncertain")
        XCTAssertEqual(BeatClassification.noiseInvalid.rawValue, "noiseInvalid")
        XCTAssertEqual(BeatClassification.notAnalyzed.rawValue, "notAnalyzed")
    }

    func testResearchDefaultsAreExplicitlyUnselected() {
        let config = ECGAlgorithmConfig.researchDefaults

        XCTAssertEqual(config.detectorIdentifier, "unselected-pending-benchmark")
        XCTAssertEqual(config.prematurityThreshold, 0.80)
        XCTAssertEqual(config.minimumTemplateBeatCount, 5)
        XCTAssertEqual(config.schemaVersion, AlgorithmVersion.configSchemaVersion)
    }
}
