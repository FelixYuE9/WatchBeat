import Foundation

public struct RPeak: Codable, Equatable, Sendable {
    public let sampleIndex: Int
    public let timeSeconds: Double
    public let confidence: Double?

    public init(sampleIndex: Int, timeSeconds: Double, confidence: Double?) {
        self.sampleIndex = sampleIndex
        self.timeSeconds = timeSeconds
        self.confidence = confidence
    }
}

public struct RejectedRPeakCandidate: Codable, Equatable, Sendable {
    public let sampleIndex: Int
    public let reasonCode: String

    public init(sampleIndex: Int, reasonCode: String) {
        self.sampleIndex = sampleIndex
        self.reasonCode = reasonCode
    }
}

public struct RPeakDetectionResult: Codable, Equatable, Sendable {
    public let peaks: [RPeak]
    public let rawCandidateSampleIndices: [Int]
    public let rejectedCandidates: [RejectedRPeakCandidate]
    public let filterDelayCorrectionSeconds: Double

    public init(
        peaks: [RPeak],
        rawCandidateSampleIndices: [Int],
        rejectedCandidates: [RejectedRPeakCandidate],
        filterDelayCorrectionSeconds: Double
    ) {
        self.peaks = peaks
        self.rawCandidateSampleIndices = rawCandidateSampleIndices
        self.rejectedCandidates = rejectedCandidates
        self.filterDelayCorrectionSeconds = filterDelayCorrectionSeconds
    }
}

public protocol RPeakDetecting: Sendable {
    func detect(in signal: ECGSignal) throws -> RPeakDetectionResult
}
