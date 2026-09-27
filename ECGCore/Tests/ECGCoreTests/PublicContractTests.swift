import Testing
@testable import ECGCore

@Suite struct PublicContractTests {
    @Test func beatClassificationRawValuesRemainExportStable() {
        #expect(BeatClassification.normal.rawValue == "normal")
        #expect(BeatClassification.possiblePAC.rawValue == "possiblePAC")
        #expect(BeatClassification.possiblePVC.rawValue == "possiblePVC")
        #expect(BeatClassification.prematureUncertain.rawValue == "prematureUncertain")
        #expect(BeatClassification.noiseInvalid.rawValue == "noiseInvalid")
        #expect(BeatClassification.notAnalyzed.rawValue == "notAnalyzed")
    }

    @Test func researchDefaultsAreExplicitlyUnselected() {
        let config = ECGAlgorithmConfig.researchDefaults

        #expect(config.detectorIdentifier == "unselected-pending-benchmark")
        #expect(config.prematurityThreshold == 0.80)
        #expect(config.minimumTemplateBeatCount == 5)
        #expect(config.schemaVersion == AlgorithmVersion.configSchemaVersion)
    }
}
