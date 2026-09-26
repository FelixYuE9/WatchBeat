import Foundation

public enum BeatClassification: String, Codable, CaseIterable, Sendable {
    case normal
    case possiblePAC
    case possiblePVC
    case prematureUncertain
    case noiseInvalid
    case notAnalyzed
}

public enum ConfidenceLevel: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case notApplicable
}

public enum ReasonCode: String, Codable, CaseIterable, Sendable {
    case prematureRelativeToLocalBaseline
    case qrsWidthSimilarToTemplate
    case qrsWidthDifferentFromTemplate
    case morphologySimilarToTemplate
    case morphologyDifferentFromTemplate
    case compensationSupportsPVC
    case nonCompensatoryPauseSupportsPAC
    case poorSignalQuality
    case usableSignalWithCaution
    case insufficientTemplate
    case unstableTemplate
    case unreliableRRContext
    case unreliableQRSBoundaries
    case conflictingMorphologyAndWidth
    case insufficientScoreMargin
    case recordBoundary
    case pWaveNotReliablyMeasurable
}

public struct BeatFeatures: Codable, Equatable, Sendable {
    public let beatIndex: Int
    public let rPeakTimeSeconds: Double
    public let rrBeforeMilliseconds: Double?
    public let rrAfterMilliseconds: Double?
    public let localRRMilliseconds: Double?
    public let prematurityRatio: Double?
    public let qrsWidthMilliseconds: Double?
    public let qrsWidthRatio: Double?
    public let morphologyCorrelation: Double?
    public let morphologyNRMSE: Double?
    public let compensationRatio: Double?

    public init(
        beatIndex: Int,
        rPeakTimeSeconds: Double,
        rrBeforeMilliseconds: Double? = nil,
        rrAfterMilliseconds: Double? = nil,
        localRRMilliseconds: Double? = nil,
        prematurityRatio: Double? = nil,
        qrsWidthMilliseconds: Double? = nil,
        qrsWidthRatio: Double? = nil,
        morphologyCorrelation: Double? = nil,
        morphologyNRMSE: Double? = nil,
        compensationRatio: Double? = nil
    ) {
        self.beatIndex = beatIndex
        self.rPeakTimeSeconds = rPeakTimeSeconds
        self.rrBeforeMilliseconds = rrBeforeMilliseconds
        self.rrAfterMilliseconds = rrAfterMilliseconds
        self.localRRMilliseconds = localRRMilliseconds
        self.prematurityRatio = prematurityRatio
        self.qrsWidthMilliseconds = qrsWidthMilliseconds
        self.qrsWidthRatio = qrsWidthRatio
        self.morphologyCorrelation = morphologyCorrelation
        self.morphologyNRMSE = morphologyNRMSE
        self.compensationRatio = compensationRatio
    }
}

public struct BeatContext: Codable, Equatable, Sendable {
    public let signalQuality: ECGQualityLevel
    public let hasStableNormalTemplate: Bool
    public let hasReliableLocalRhythm: Bool

    public init(
        signalQuality: ECGQualityLevel,
        hasStableNormalTemplate: Bool,
        hasReliableLocalRhythm: Bool
    ) {
        self.signalQuality = signalQuality
        self.hasStableNormalTemplate = hasStableNormalTemplate
        self.hasReliableLocalRhythm = hasReliableLocalRhythm
    }
}

public struct BeatClassificationResult: Codable, Equatable, Sendable {
    public let classification: BeatClassification
    public let confidence: ConfidenceLevel
    public let featureSnapshot: BeatFeatures
    public let supportingReasons: [ReasonCode]
    public let conflictingReasons: [ReasonCode]
    public let algorithmVersion: String
    public let configVersion: String

    public init(
        classification: BeatClassification,
        confidence: ConfidenceLevel,
        featureSnapshot: BeatFeatures,
        supportingReasons: [ReasonCode],
        conflictingReasons: [ReasonCode],
        algorithmVersion: String,
        configVersion: String
    ) {
        self.classification = classification
        self.confidence = confidence
        self.featureSnapshot = featureSnapshot
        self.supportingReasons = supportingReasons
        self.conflictingReasons = conflictingReasons
        self.algorithmVersion = algorithmVersion
        self.configVersion = configVersion
    }
}

public protocol BeatClassifying: Sendable {
    func classify(
        beat: BeatFeatures,
        context: BeatContext,
        config: ECGAlgorithmConfig
    ) -> BeatClassificationResult
}
