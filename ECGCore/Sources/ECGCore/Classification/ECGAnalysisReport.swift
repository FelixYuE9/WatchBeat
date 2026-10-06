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

/// Additive schema-v1 timing metrics derived only from this report's detected R peaks.
///
/// These values are descriptive research measurements. In particular,
/// `rrInterquartileRangeMilliseconds` is not a clinical HRV result.
public struct ECGRhythmMetrics: Codable, Equatable, Sendable {
    public static let currentVersion = "watchbeat.rr-summary.v1"

    public let metricsVersion: String
    public let recordingDurationSeconds: Double
    public let plausibleRRIntervalCount: Int
    public let medianRRMilliseconds: Double
    public let medianDetectedHeartRateBPM: Double
    public let rrInterquartileRangeMilliseconds: Double
    public let prematureCandidateFraction: Double

    public init(
        metricsVersion: String = ECGRhythmMetrics.currentVersion,
        recordingDurationSeconds: Double,
        plausibleRRIntervalCount: Int,
        medianRRMilliseconds: Double,
        medianDetectedHeartRateBPM: Double,
        rrInterquartileRangeMilliseconds: Double,
        prematureCandidateFraction: Double
    ) {
        self.metricsVersion = metricsVersion
        self.recordingDurationSeconds = recordingDurationSeconds
        self.plausibleRRIntervalCount = plausibleRRIntervalCount
        self.medianRRMilliseconds = medianRRMilliseconds
        self.medianDetectedHeartRateBPM = medianDetectedHeartRateBPM
        self.rrInterquartileRangeMilliseconds = rrInterquartileRangeMilliseconds
        self.prematureCandidateFraction = prematureCandidateFraction
    }
}

/// Additive schema-v1 descriptive values for one recording, derived from this report's R peaks and
/// the original samples.
///
/// None of these is a diagnosis. A long R–R interval can come from a pause or from an R peak the
/// detector missed, and QRS peak-to-trough voltage depends on wrist contact and posture.
public struct ECGRecordingDescriptors: Codable, Equatable, Sendable {
    public static let currentVersion = "watchbeat.descriptors.v1"
    /// R–R intervals longer than this are counted, not used for rate statistics.
    public static let longRRThresholdMilliseconds = 2_000.0

    public let descriptorsVersion: String
    /// Over every interval between consecutive detected R peaks.
    public let shortestRRMilliseconds: Double
    public let longestRRMilliseconds: Double
    /// Beat-to-beat rate range from plausible (300–2,000 ms) intervals only.
    public let minimumInstantaneousHeartRateBPM: Double?
    public let maximumInstantaneousHeartRateBPM: Double?
    public let longRRIntervalCount: Int
    /// Adjacent beat pairs that are both `prematureUncertain`.
    public let consecutiveCandidatePairCount: Int
    /// Raw-signal max − min within ±`ECGQRSAmplitude.halfWindowMilliseconds` of each R peak.
    public let medianQRSPeakToTroughMillivolts: Double?
    public let minimumQRSPeakToTroughMillivolts: Double?
    public let maximumQRSPeakToTroughMillivolts: Double?

    public init(
        descriptorsVersion: String = ECGRecordingDescriptors.currentVersion,
        shortestRRMilliseconds: Double,
        longestRRMilliseconds: Double,
        minimumInstantaneousHeartRateBPM: Double?,
        maximumInstantaneousHeartRateBPM: Double?,
        longRRIntervalCount: Int,
        consecutiveCandidatePairCount: Int,
        medianQRSPeakToTroughMillivolts: Double?,
        minimumQRSPeakToTroughMillivolts: Double?,
        maximumQRSPeakToTroughMillivolts: Double?
    ) {
        self.descriptorsVersion = descriptorsVersion
        self.shortestRRMilliseconds = shortestRRMilliseconds
        self.longestRRMilliseconds = longestRRMilliseconds
        self.minimumInstantaneousHeartRateBPM = minimumInstantaneousHeartRateBPM
        self.maximumInstantaneousHeartRateBPM = maximumInstantaneousHeartRateBPM
        self.longRRIntervalCount = longRRIntervalCount
        self.consecutiveCandidatePairCount = consecutiveCandidatePairCount
        self.medianQRSPeakToTroughMillivolts = medianQRSPeakToTroughMillivolts
        self.minimumQRSPeakToTroughMillivolts = minimumQRSPeakToTroughMillivolts
        self.maximumQRSPeakToTroughMillivolts = maximumQRSPeakToTroughMillivolts
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
    /// Additive and optional so older schema-v1 JSON remains decodable. Descriptive only; it
    /// never influences `classification`.
    public let qrsPeakToTroughMillivolts: Double?

    public init(
        sampleIndex: Int,
        timeSeconds: Double,
        rrBeforeMilliseconds: Double?,
        localRRMilliseconds: Double?,
        prematurityRatio: Double?,
        classification: BeatClassification,
        confidence: ConfidenceLevel,
        reasonCodes: [ReasonCode],
        qrsPeakToTroughMillivolts: Double? = nil
    ) {
        self.sampleIndex = sampleIndex
        self.timeSeconds = timeSeconds
        self.rrBeforeMilliseconds = rrBeforeMilliseconds
        self.localRRMilliseconds = localRRMilliseconds
        self.prematurityRatio = prematurityRatio
        self.classification = classification
        self.confidence = confidence
        self.reasonCodes = reasonCodes
        self.qrsPeakToTroughMillivolts = qrsPeakToTroughMillivolts
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
    /// Optional so older schema-v1 JSON without this additive field remains decodable.
    public let rhythmMetrics: ECGRhythmMetrics?
    /// Additive like `rhythmMetrics`; absent from refusals and older JSON.
    public let recordingDescriptors: ECGRecordingDescriptors?
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
        rhythmMetrics: ECGRhythmMetrics? = nil,
        recordingDescriptors: ECGRecordingDescriptors? = nil,
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
        self.rhythmMetrics = rhythmMetrics
        self.recordingDescriptors = recordingDescriptors
        self.beats = beats
    }
}

public protocol ECGAnalyzing: Sendable {
    func analyze(_ signal: ECGSignal) -> ECGAnalysisReport
}
