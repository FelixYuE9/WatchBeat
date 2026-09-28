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
    public let refractoryPeriodMilliseconds: Double
    public let peakRefinementRadiusMilliseconds: Double
    public let rrBaselineWindowBeats: Int
    public let minimumRRBaselineBeatCount: Int
    public let prematurityThreshold: Double
    public let maximumSamplingIntervalRelativeMAD: Double

    public init(
        schemaVersion: String,
        detectorIdentifier: String,
        detectionFilter: FilterConfiguration,
        refractoryPeriodMilliseconds: Double,
        peakRefinementRadiusMilliseconds: Double,
        rrBaselineWindowBeats: Int,
        minimumRRBaselineBeatCount: Int,
        prematurityThreshold: Double,
        maximumSamplingIntervalRelativeMAD: Double
    ) {
        self.schemaVersion = schemaVersion
        self.detectorIdentifier = detectorIdentifier
        self.detectionFilter = detectionFilter
        self.refractoryPeriodMilliseconds = refractoryPeriodMilliseconds
        self.peakRefinementRadiusMilliseconds = peakRefinementRadiusMilliseconds
        self.rrBaselineWindowBeats = rrBaselineWindowBeats
        self.minimumRRBaselineBeatCount = minimumRRBaselineBeatCount
        self.prematurityThreshold = prematurityThreshold
        self.maximumSamplingIntervalRelativeMAD = maximumSamplingIntervalRelativeMAD
    }

    public static let researchDefaults = ECGAlgorithmConfig(
        schemaVersion: AlgorithmVersion.configSchemaVersion,
        detectorIdentifier: "watchbeat-gradient-energy-rr-v1",
        detectionFilter: FilterConfiguration(
            lowCutoffHz: 5.0,
            highCutoffHz: 25.0,
            order: 2,
            usesZeroPhaseFiltering: true
        ),
        refractoryPeriodMilliseconds: 250.0,
        peakRefinementRadiusMilliseconds: 100.0,
        rrBaselineWindowBeats: 8,
        minimumRRBaselineBeatCount: 4,
        prematurityThreshold: 0.80,
        maximumSamplingIntervalRelativeMAD: 0.05
    )
}
