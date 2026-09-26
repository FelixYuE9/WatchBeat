import Foundation

public struct FilterConfiguration: Codable, Equatable, Sendable {
    public let lowCutoffHz: Double
    public let highCutoffHz: Double
    public let order: Int
    public let usesZeroPhaseFiltering: Bool

    public init(
        lowCutoffHz: Double,
        highCutoffHz: Double,
        order: Int,
        usesZeroPhaseFiltering: Bool
    ) {
        self.lowCutoffHz = lowCutoffHz
        self.highCutoffHz = highCutoffHz
        self.order = order
        self.usesZeroPhaseFiltering = usesZeroPhaseFiltering
    }
}

/// Versioned research parameters. Defaults are hypotheses, not medical thresholds.
public struct ECGAlgorithmConfig: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let detectorIdentifier: String
    public let detectionFilter: FilterConfiguration
    public let morphologyFilter: FilterConfiguration
    public let refractoryPeriodMilliseconds: Double
    public let peakRefinementRadiusMilliseconds: Double
    public let rrBaselineWindowBeats: Int
    public let prematurityThreshold: Double
    public let morphologyWindowBeforeRMilliseconds: Double
    public let morphologyWindowAfterRMilliseconds: Double
    public let templateAlignmentRadiusMilliseconds: Double
    public let minimumTemplateBeatCount: Int
    public let morphologyCorrelationThreshold: Double
    public let morphologyNRMSEThreshold: Double
    public let qrsWidthRatioThreshold: Double
    public let compensationTolerance: Double
    public let maximumSamplingIntervalRelativeMAD: Double
    public let classificationScoreThreshold: Double
    public let classificationScoreMargin: Double

    public init(
        schemaVersion: String,
        detectorIdentifier: String,
        detectionFilter: FilterConfiguration,
        morphologyFilter: FilterConfiguration,
        refractoryPeriodMilliseconds: Double,
        peakRefinementRadiusMilliseconds: Double,
        rrBaselineWindowBeats: Int,
        prematurityThreshold: Double,
        morphologyWindowBeforeRMilliseconds: Double,
        morphologyWindowAfterRMilliseconds: Double,
        templateAlignmentRadiusMilliseconds: Double,
        minimumTemplateBeatCount: Int,
        morphologyCorrelationThreshold: Double,
        morphologyNRMSEThreshold: Double,
        qrsWidthRatioThreshold: Double,
        compensationTolerance: Double,
        maximumSamplingIntervalRelativeMAD: Double,
        classificationScoreThreshold: Double,
        classificationScoreMargin: Double
    ) {
        self.schemaVersion = schemaVersion
        self.detectorIdentifier = detectorIdentifier
        self.detectionFilter = detectionFilter
        self.morphologyFilter = morphologyFilter
        self.refractoryPeriodMilliseconds = refractoryPeriodMilliseconds
        self.peakRefinementRadiusMilliseconds = peakRefinementRadiusMilliseconds
        self.rrBaselineWindowBeats = rrBaselineWindowBeats
        self.prematurityThreshold = prematurityThreshold
        self.morphologyWindowBeforeRMilliseconds = morphologyWindowBeforeRMilliseconds
        self.morphologyWindowAfterRMilliseconds = morphologyWindowAfterRMilliseconds
        self.templateAlignmentRadiusMilliseconds = templateAlignmentRadiusMilliseconds
        self.minimumTemplateBeatCount = minimumTemplateBeatCount
        self.morphologyCorrelationThreshold = morphologyCorrelationThreshold
        self.morphologyNRMSEThreshold = morphologyNRMSEThreshold
        self.qrsWidthRatioThreshold = qrsWidthRatioThreshold
        self.compensationTolerance = compensationTolerance
        self.maximumSamplingIntervalRelativeMAD = maximumSamplingIntervalRelativeMAD
        self.classificationScoreThreshold = classificationScoreThreshold
        self.classificationScoreMargin = classificationScoreMargin
    }

    public static let researchDefaults = ECGAlgorithmConfig(
        schemaVersion: "0.1.0",
        detectorIdentifier: "unselected-pending-benchmark",
        detectionFilter: FilterConfiguration(
            lowCutoffHz: 5.0,
            highCutoffHz: 20.0,
            order: 2,
            usesZeroPhaseFiltering: true
        ),
        morphologyFilter: FilterConfiguration(
            lowCutoffHz: 0.5,
            highCutoffHz: 40.0,
            order: 2,
            usesZeroPhaseFiltering: true
        ),
        refractoryPeriodMilliseconds: 250.0,
        peakRefinementRadiusMilliseconds: 80.0,
        rrBaselineWindowBeats: 8,
        prematurityThreshold: 0.80,
        morphologyWindowBeforeRMilliseconds: 120.0,
        morphologyWindowAfterRMilliseconds: 200.0,
        templateAlignmentRadiusMilliseconds: 20.0,
        minimumTemplateBeatCount: 5,
        morphologyCorrelationThreshold: 0.90,
        morphologyNRMSEThreshold: 0.25,
        qrsWidthRatioThreshold: 1.20,
        compensationTolerance: 0.15,
        maximumSamplingIntervalRelativeMAD: 0.05,
        classificationScoreThreshold: 2.0,
        classificationScoreMargin: 1.0
    )
}
