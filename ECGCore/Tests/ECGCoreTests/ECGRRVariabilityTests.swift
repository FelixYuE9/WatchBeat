import Foundation
import Testing
@testable import ECGCore

@Suite struct ECGRRVariabilityTests {
    @Test func handCalculatedVectorMatchesSampleStatistics() throws {
        let metrics = try #require(measure([800, 1_000, 1_200]))
        #expect(abs(metrics.meanRRMilliseconds - 1_000) < 1e-8)
        #expect(abs(metrics.sdrrMilliseconds - 200) < 1e-8)
        #expect(abs(metrics.coefficientOfVariationPercent - 20) < 1e-8)
        #expect(abs((metrics.successiveDifferenceRMSMilliseconds ?? -1) - 200) < 1e-8)
        #expect(metrics.successiveDifferenceOver50MillisecondsPercent == 100)
        #expect(metrics.successivePairCount == 2)
        #expect(metrics.excludedIntervalCount == 0)
    }

    @Test func constantIntervalsHaveZeroVariability() throws {
        let metrics = try #require(measure([1_000, 1_000, 1_000]))
        #expect(metrics.sdrrMilliseconds == 0)
        #expect(metrics.coefficientOfVariationPercent == 0)
        #expect(metrics.successiveDifferenceRMSMilliseconds == 0)
        #expect(metrics.successiveDifferenceOver50MillisecondsPercent == 0)
    }

    @Test func excludedIntervalsNeverCreateArtificialAdjacentPairs() throws {
        let metrics = try #require(measure([800, 2_500, 1_000]))
        #expect(metrics.detectedIntervalCount == 3)
        #expect(metrics.includedIntervalCount == 2)
        #expect(metrics.excludedIntervalCount == 1)
        #expect(metrics.successivePairCount == 0)
        #expect(metrics.successiveDifferenceRMSMilliseconds == nil)
        #expect(metrics.successiveDifferenceOver50MillisecondsPercent == nil)

        let withOnePair = try #require(measure([800, 2_500, 1_000, 1_200]))
        #expect(withOnePair.successivePairCount == 1)
        #expect(abs((withOnePair.successiveDifferenceRMSMilliseconds ?? -1) - 200) < 1e-8)
    }

    @Test func fiftyMillisecondsIsStrictlyExcludedFromOver50Count() throws {
        let metrics = try #require(measure([800, 850, 900]))
        #expect(metrics.successiveDifferenceOver50MillisecondsPercent == 0)
        let above = try #require(measure([800, 850.1, 900.2]))
        #expect(above.successiveDifferenceOver50MillisecondsPercent == 100)
    }

    @Test func candidatesRemainInRawRRButAreCountedWithoutDoubleCounting() throws {
        let beats = makeBeats([800, 1_000, 1_200], candidates: [1, 2])
        let metrics = try #require(ECGRRVariabilityMetrics.measure(beats: beats, recordingDurationSeconds: 30))
        #expect(metrics.candidateAdjacentIntervalCount == 3)
        #expect(metrics.includedIntervalCount == 3)
        #expect(abs(metrics.coefficientOfVariationPercent - 20) < 1e-8)
    }

    @Test func rangeBoundsAndSmallInputsAreExplicit() throws {
        #expect(measure([]) == nil)
        #expect(measure([1_000]) == nil)
        #expect(measure([200, 2_500]) == nil)
        let metrics = try #require(measure([300, 2_000]))
        #expect(metrics.includedIntervalCount == 2)
        #expect(ECGRRVariabilityMetrics.measure(beats: makeBeats([800, 900]), recordingDurationSeconds: .nan) == nil)
        let badTimes = makeBeats([.nan, 1_000])
        #expect(ECGRRVariabilityMetrics.plausibleIntervals(from: badTimes).allSatisfy { $0 == nil })
    }

    @Test func metricsRoundTripAndOldReportDecodesWithoutAdditiveField() throws {
        let beats = makeBeats([800, 1_000, 1_200])
        let metrics = try #require(measure([800, 1_000, 1_200]))
        let report = ECGAnalysisReport(
            algorithmVersion: AlgorithmVersion.semanticVersion,
            configVersion: AlgorithmVersion.configSchemaVersion,
            detectorIdentifier: ECGAlgorithmConfig.researchDefaults.detectorIdentifier,
            parameters: ECGAnalysisParameters(config: .researchDefaults),
            status: .analyzed, reason: nil, samplingFrequencyHz: 500,
            summary: ECGAnalysisSummary(rPeakCount: 4, classifiedBeatCount: 4, prematureCandidateCount: 0),
            rrVariability: metrics, beats: beats
        )
        let data = try JSONEncoder().encode(report)
        #expect(try JSONDecoder().decode(ECGAnalysisReport.self, from: data) == report)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "rrVariability")
        let oldData = try JSONSerialization.data(withJSONObject: json)
        let old = try JSONDecoder().decode(ECGAnalysisReport.self, from: oldData)
        #expect(old.rrVariability == nil)
        #expect(old.beats == report.beats)
    }

    private func measure(_ rr: [Double]) -> ECGRRVariabilityMetrics? {
        ECGRRVariabilityMetrics.measure(beats: makeBeats(rr), recordingDurationSeconds: 30)
    }

    private func makeBeats(_ rr: [Double], candidates: Set<Int> = []) -> [ECGAnalyzedBeat] {
        var time = 0.0
        var times = [time]
        for interval in rr {
            time += interval / 1_000
            times.append(time)
        }
        return times.enumerated().map { index, time in
            ECGAnalyzedBeat(
                sampleIndex: index, timeSeconds: time,
                rrBeforeMilliseconds: index > 0 ? rr[index - 1] : nil,
                localRRMilliseconds: nil, prematurityRatio: nil,
                classification: candidates.contains(index) ? .prematureUncertain : .normal,
                confidence: .low, reasonCodes: []
            )
        }
    }
}
