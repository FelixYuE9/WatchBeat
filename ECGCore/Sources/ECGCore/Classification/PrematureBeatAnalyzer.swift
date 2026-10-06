import Foundation

/// Dependency-free Swift port of the repository's proven minimal vertical slice.
///
/// The model performs a Pan-Tompkins-style gradient-energy R-peak pass followed by the same
/// rolling-median RR rule as `Tools/Validation/prototype_premature_beats.py`. It deliberately
/// stops at `prematureUncertain`; RR timing alone is not used to invent a PAC/PVC subtype.
public struct PrematureBeatAnalyzer: ECGAnalyzing, Sendable {
    public let config: ECGAlgorithmConfig

    public init(config: ECGAlgorithmConfig = .researchDefaults) {
        self.config = config
    }

    public func analyze(_ signal: ECGSignal) -> ECGAnalysisReport {
        guard hasSupportedConfiguration else {
            return refusal(.unsupportedConfiguration)
        }
        guard signal.timeSeconds.count == signal.voltageMillivolts.count,
              signal.timeSeconds.count >= 2 else {
            return refusal(.missingOrMismatchedSamples)
        }

        let times = signal.timeSeconds
        guard let voltage = finiteVoltage(from: signal) else {
            return refusal(.missingOrNonFiniteSamples)
        }
        guard let intervals = positiveIntervals(from: times) else {
            return refusal(.invalidTimestamps)
        }
        guard let medianInterval = Self.median(intervals), medianInterval > 0 else {
            return refusal(.invalidTimestamps)
        }

        let frequencyHz = 1.0 / medianInterval
        let deviations = intervals.map { abs($0 - medianInterval) }
        let relativeMAD = (Self.median(deviations) ?? .infinity) / medianInterval
        let duration = times[times.count - 1] - times[0]
        guard frequencyHz >= 60,
              frequencyHz <= 1_000,
              relativeMAD <= config.maximumSamplingIntervalRelativeMAD,
              (intervals.max() ?? .infinity) <= 1.5 * medianInterval,
              duration >= 8 else {
            return refusal(.unsupportedSamplingOrDuration, samplingFrequencyHz: frequencyHz)
        }

        let peaks = GradientEnergyRPeakDetector.detect(
            voltageMillivolts: voltage,
            samplingFrequencyHz: frequencyHz,
            lowCutoffHz: config.detectionFilter.lowCutoffHz,
            highCutoffHz: config.detectionFilter.highCutoffHz,
            refractoryPeriodMilliseconds: config.refractoryPeriodMilliseconds,
            refinementRadiusMilliseconds: config.peakRefinementRadiusMilliseconds
        )
        guard peaks.count >= config.minimumRRBaselineBeatCount + 2 else {
            return refusal(.insufficientDetectedBeats, samplingFrequencyHz: frequencyHz)
        }

        let rrMilliseconds = (1..<peaks.count).map { index in
            (times[peaks[index]] - times[peaks[index - 1]]) * 1_000
        }
        // Descriptive only: measured after detection and never read by the RR rule below.
        let qrsAmplitudes = peaks.map { peak in
            ECGQRSAmplitude.measure(
                voltageMillivolts: signal.voltageMillivolts,
                around: peak,
                samplingFrequencyHz: frequencyHz
            )?.peakToTroughMillivolts
        }
        let result = classify(
            peaks: peaks,
            rrMilliseconds: rrMilliseconds,
            times: times,
            qrsAmplitudes: qrsAmplitudes
        )
        guard result.classifiedBeatCount > 0 else {
            return refusal(.insufficientReliableRRContext, samplingFrequencyHz: frequencyHz)
        }
        let rhythmMetrics = makeRhythmMetrics(
            rrMilliseconds: rrMilliseconds,
            recordingDurationSeconds: duration,
            classifiedBeatCount: result.classifiedBeatCount,
            prematureCandidateCount: result.prematureCandidateCount
        )
        let recordingDescriptors = makeRecordingDescriptors(
            rrMilliseconds: rrMilliseconds,
            beats: result.beats,
            qrsAmplitudes: qrsAmplitudes.compactMap { $0 }
        )

        return ECGAnalysisReport(
            algorithmVersion: AlgorithmVersion.semanticVersion,
            configVersion: config.schemaVersion,
            detectorIdentifier: config.detectorIdentifier,
            parameters: ECGAnalysisParameters(config: config),
            status: .analyzed,
            reason: nil,
            samplingFrequencyHz: frequencyHz,
            summary: ECGAnalysisSummary(
                rPeakCount: result.beats.count,
                classifiedBeatCount: result.classifiedBeatCount,
                prematureCandidateCount: result.prematureCandidateCount
            ),
            rhythmMetrics: rhythmMetrics,
            recordingDescriptors: recordingDescriptors,
            beats: result.beats
        )
    }

    private var hasSupportedConfiguration: Bool {
        config.detectionFilter.order == 2
            && config.detectionFilter.usesZeroPhaseFiltering
            && config.detectionFilter.lowCutoffHz.isFinite
            && config.detectionFilter.highCutoffHz.isFinite
            && config.detectionFilter.lowCutoffHz > 0
            && config.detectionFilter.highCutoffHz > config.detectionFilter.lowCutoffHz
            && config.refractoryPeriodMilliseconds.isFinite
            && config.refractoryPeriodMilliseconds > 0
            && config.peakRefinementRadiusMilliseconds.isFinite
            && config.peakRefinementRadiusMilliseconds > 0
            && config.minimumRRBaselineBeatCount > 0
            && config.rrBaselineWindowBeats >= config.minimumRRBaselineBeatCount
            && config.prematurityThreshold.isFinite
            && config.prematurityThreshold > 0
            && config.prematurityThreshold < 1
            && config.maximumSamplingIntervalRelativeMAD.isFinite
            && config.maximumSamplingIntervalRelativeMAD >= 0
    }

    private func finiteVoltage(from signal: ECGSignal) -> [Double]? {
        var voltage: [Double] = []
        voltage.reserveCapacity(signal.voltageMillivolts.count)
        for index in signal.timeSeconds.indices {
            guard signal.timeSeconds[index].isFinite,
                  let value = signal.voltageMillivolts[index],
                  value.isFinite else {
                return nil
            }
            voltage.append(value)
        }
        return voltage
    }

    private func positiveIntervals(from times: [Double]) -> [Double]? {
        var intervals: [Double] = []
        intervals.reserveCapacity(times.count - 1)
        for index in 1..<times.count {
            let interval = times[index] - times[index - 1]
            guard interval.isFinite, interval > 0 else { return nil }
            intervals.append(interval)
        }
        return intervals
    }

    private func classify(
        peaks: [Int],
        rrMilliseconds: [Double],
        times: [Double],
        qrsAmplitudes: [Double?]
    ) -> (beats: [ECGAnalyzedBeat], classifiedBeatCount: Int, prematureCandidateCount: Int) {
        var beats: [ECGAnalyzedBeat] = []
        beats.reserveCapacity(peaks.count)
        var classifiedBeatCount = 0
        var prematureCandidateCount = 0

        for peakPosition in peaks.indices {
            let previousRR = peakPosition > 0 ? rrMilliseconds[peakPosition - 1] : nil
            let contextUpperBound = max(0, peakPosition - 1)
            let contextLowerBound = max(0, contextUpperBound - config.rrBaselineWindowBeats)
            let context = contextLowerBound < contextUpperBound
                ? rrMilliseconds[contextLowerBound..<contextUpperBound].filter { 300...2_000 ~= $0 }
                : []
            let localRR = context.count >= config.minimumRRBaselineBeatCount
                ? Self.median(Array(context))
                : nil
            let ratio = previousRR.flatMap { rr in localRR.map { rr / $0 } }
            let isPremature = previousRR.map { rr in
                guard let localRR else { return false }
                return rr >= 300 && rr < config.prematurityThreshold * localRR
            } ?? false

            let classification: BeatClassification
            let confidence: ConfidenceLevel
            let reasons: [ReasonCode]
            if localRR == nil {
                classification = .notAnalyzed
                confidence = .notApplicable
                reasons = [.unreliableRRContext]
            } else if isPremature {
                classification = .prematureUncertain
                confidence = .low
                reasons = [.prematureRelativeToLocalBaseline]
                classifiedBeatCount += 1
                prematureCandidateCount += 1
            } else {
                classification = .normal
                confidence = .low
                reasons = []
                classifiedBeatCount += 1
            }

            beats.append(
                ECGAnalyzedBeat(
                    sampleIndex: peaks[peakPosition],
                    timeSeconds: times[peaks[peakPosition]],
                    rrBeforeMilliseconds: previousRR,
                    localRRMilliseconds: localRR,
                    prematurityRatio: ratio,
                    classification: classification,
                    confidence: confidence,
                    reasonCodes: reasons,
                    qrsPeakToTroughMillivolts: qrsAmplitudes[peakPosition]
                )
            )
        }
        return (beats, classifiedBeatCount, prematureCandidateCount)
    }

    private func makeRhythmMetrics(
        rrMilliseconds: [Double],
        recordingDurationSeconds: Double,
        classifiedBeatCount: Int,
        prematureCandidateCount: Int
    ) -> ECGRhythmMetrics? {
        let plausibleRR = rrMilliseconds.filter { 300...2_000 ~= $0 }
        guard let medianRR = Self.median(plausibleRR),
              medianRR > 0,
              let lowerQuartile = Self.quantile(plausibleRR, probability: 0.25),
              let upperQuartile = Self.quantile(plausibleRR, probability: 0.75),
              classifiedBeatCount > 0 else {
            return nil
        }

        return ECGRhythmMetrics(
            recordingDurationSeconds: recordingDurationSeconds,
            plausibleRRIntervalCount: plausibleRR.count,
            medianRRMilliseconds: medianRR,
            medianDetectedHeartRateBPM: 60_000 / medianRR,
            rrInterquartileRangeMilliseconds: upperQuartile - lowerQuartile,
            prematureCandidateFraction: Double(prematureCandidateCount)
                / Double(classifiedBeatCount)
        )
    }

    private func makeRecordingDescriptors(
        rrMilliseconds: [Double],
        beats: [ECGAnalyzedBeat],
        qrsAmplitudes: [Double]
    ) -> ECGRecordingDescriptors? {
        guard let shortestRR = rrMilliseconds.min(),
              let longestRR = rrMilliseconds.max() else {
            return nil
        }
        let plausibleRR = rrMilliseconds.filter { 300...2_000 ~= $0 }
        let consecutivePairs = zip(beats, beats.dropFirst()).filter { pair in
            pair.0.classification == .prematureUncertain
                && pair.1.classification == .prematureUncertain
        }.count

        return ECGRecordingDescriptors(
            shortestRRMilliseconds: shortestRR,
            longestRRMilliseconds: longestRR,
            minimumInstantaneousHeartRateBPM: plausibleRR.max().map { 60_000 / $0 },
            maximumInstantaneousHeartRateBPM: plausibleRR.min().map { 60_000 / $0 },
            longRRIntervalCount: rrMilliseconds.filter {
                $0 > ECGRecordingDescriptors.longRRThresholdMilliseconds
            }.count,
            consecutiveCandidatePairCount: consecutivePairs,
            medianQRSPeakToTroughMillivolts: Self.median(qrsAmplitudes),
            minimumQRSPeakToTroughMillivolts: qrsAmplitudes.min(),
            maximumQRSPeakToTroughMillivolts: qrsAmplitudes.max()
        )
    }

    private func refusal(
        _ reason: ECGAnalysisReason,
        samplingFrequencyHz: Double? = nil
    ) -> ECGAnalysisReport {
        ECGAnalysisReport(
            algorithmVersion: AlgorithmVersion.semanticVersion,
            configVersion: config.schemaVersion,
            detectorIdentifier: config.detectorIdentifier,
            parameters: ECGAnalysisParameters(config: config),
            status: .notAnalyzed,
            reason: reason,
            samplingFrequencyHz: samplingFrequencyHz,
            summary: ECGAnalysisSummary(
                rPeakCount: 0,
                classifiedBeatCount: 0,
                prematureCandidateCount: 0
            ),
            beats: []
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    /// Linear interpolation between adjacent ranks (the common type-7 sample quantile).
    private static func quantile(_ values: [Double], probability: Double) -> Double? {
        guard !values.isEmpty, 0...1 ~= probability else { return nil }
        let sorted = values.sorted()
        let position = Double(sorted.count - 1) * probability
        let lowerIndex = Int(floor(position))
        let upperIndex = Int(ceil(position))
        guard lowerIndex != upperIndex else { return sorted[lowerIndex] }
        let fraction = position - Double(lowerIndex)
        return sorted[lowerIndex] + fraction * (sorted[upperIndex] - sorted[lowerIndex])
    }
}
