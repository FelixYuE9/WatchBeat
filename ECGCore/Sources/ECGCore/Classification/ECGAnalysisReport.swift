import Foundation

/// Product result vocabulary. Raw values are part of the exported JSON contract.
/// The v1 analyzer only emits `normal`, `prematureUncertain` and `notAnalyzed`; the other
/// cases are reserved so a later PAC/PVC model does not change the schema.
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
    case unreliableRRContext
}

/// Stable, platform-neutral output status for the on-device analysis boundary.
public enum ECGAnalysisStatus: String, Codable, Equatable, Sendable {
    case analyzed
    case notAnalyzed
}

/// A machine-readable refusal reason. A refused signal never produces beat classifications.
public enum ECGAnalysisReason: String, Codable, Equatable, Sendable {
    case missingOrMismatchedSamples
    case missingOrNonFiniteSamples
    case invalidTimestamps
    case unsupportedSamplingOrDuration
    case unsupportedConfiguration
    case insufficientDetectedBeats
    case insufficientReliableRRContext
}

public struct ECGAnalysisSummary: Codable, Equatable, Sendable {
    public let rPeakCount: Int
    public let classifiedBeatCount: Int
    public let prematureCandidateCount: Int

    public init(
        rPeakCount: Int,
        classifiedBeatCount: Int,
        prematureCandidateCount: Int
    ) {
        self.rPeakCount = rPeakCount
        self.classifiedBeatCount = classifiedBeatCount
        self.prematureCandidateCount = prematureCandidateCount
    }
}

/// Result-affecting values copied into every report for auditability.
public struct ECGAnalysisParameters: Codable, Equatable, Sendable {
    public let detectionLowCutoffHz: Double
    public let detectionHighCutoffHz: Double
    public let refractoryPeriodMilliseconds: Double
    public let peakRefinementRadiusMilliseconds: Double
    public let rrBaselineWindowBeats: Int
    public let minimumRRBaselineBeatCount: Int
    public let prematurityThreshold: Double

    public init(config: ECGAlgorithmConfig) {
        self.detectionLowCutoffHz = config.detectionFilter.lowCutoffHz
        self.detectionHighCutoffHz = config.detectionFilter.highCutoffHz
        self.refractoryPeriodMilliseconds = config.refractoryPeriodMilliseconds
        self.peakRefinementRadiusMilliseconds = config.peakRefinementRadiusMilliseconds
        self.rrBaselineWindowBeats = config.rrBaselineWindowBeats
        self.minimumRRBaselineBeatCount = config.minimumRRBaselineBeatCount
        self.prematurityThreshold = config.prematurityThreshold
    }
}

/// One detector peak and the RR-only research classification made for it.
///
/// `sampleIndex` always addresses the original `ECGSignal`; the analyzer never resamples,
/// reorders, deletes or interpolates input samples.
public struct ECGAnalyzedBeat: Codable, Equatable, Sendable {
    public let sampleIndex: Int
    public let timeSeconds: Double
    public let rrBeforeMilliseconds: Double?
    public let localRRMilliseconds: Double?
    public let prematurityRatio: Double?
    public let classification: BeatClassification
    public let confidence: ConfidenceLevel
    public let reasonCodes: [ReasonCode]

    public init(
        sampleIndex: Int,
        timeSeconds: Double,
        rrBeforeMilliseconds: Double?,
        localRRMilliseconds: Double?,
        prematurityRatio: Double?,
        classification: BeatClassification,
        confidence: ConfidenceLevel,
        reasonCodes: [ReasonCode]
    ) {
        self.sampleIndex = sampleIndex
        self.timeSeconds = timeSeconds
        self.rrBeforeMilliseconds = rrBeforeMilliseconds
        self.localRRMilliseconds = localRRMilliseconds
        self.prematurityRatio = prematurityRatio
        self.classification = classification
        self.confidence = confidence
        self.reasonCodes = reasonCodes
    }
}

/// Versioned output contract shared by synthetic and HealthKit-backed signals.
public struct ECGAnalysisReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let algorithmVersion: String
    public let configVersion: String
    public let detectorIdentifier: String
    public let researchOnly: Bool
    public let inputFormat: String
    public let parameters: ECGAnalysisParameters
    public let status: ECGAnalysisStatus
    public let reason: ECGAnalysisReason?
    public let samplingFrequencyHz: Double?
    public let summary: ECGAnalysisSummary
    public let beats: [ECGAnalyzedBeat]

    public init(
        schemaVersion: Int = 1,
        algorithmVersion: String,
        configVersion: String,
        detectorIdentifier: String,
        researchOnly: Bool = true,
        inputFormat: String = ECGSignal.formatIdentifier,
        parameters: ECGAnalysisParameters,
        status: ECGAnalysisStatus,
        reason: ECGAnalysisReason?,
        samplingFrequencyHz: Double?,
        summary: ECGAnalysisSummary,
        beats: [ECGAnalyzedBeat]
    ) {
        self.schemaVersion = schemaVersion
        self.algorithmVersion = algorithmVersion
        self.configVersion = configVersion
        self.detectorIdentifier = detectorIdentifier
        self.researchOnly = researchOnly
        self.inputFormat = inputFormat
        self.parameters = parameters
        self.status = status
        self.reason = reason
        self.samplingFrequencyHz = samplingFrequencyHz
        self.summary = summary
        self.beats = beats
    }
}

public protocol ECGAnalyzing: Sendable {
    func analyze(_ signal: ECGSignal) -> ECGAnalysisReport
}
