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

    @Test func researchDefaultsSelectTheShippableVerticalSlice() {
        let config = ECGAlgorithmConfig.researchDefaults

        #expect(config.detectorIdentifier == "watchbeat-gradient-energy-rr-v1")
        #expect(config.prematurityThreshold == 0.80)
        #expect(config.minimumRRBaselineBeatCount == 4)
        #expect(config.schemaVersion == AlgorithmVersion.configSchemaVersion)
        #expect(AlgorithmVersion.semanticVersion == "1.0.1-rr-research")
    }

    @Test func canonicalSignalContractIsStable() {
        #expect(ECGSignal.formatIdentifier == "watchbeat.ecg.signal.v1")
        #expect(ECGSignal.schemaVersion == 1)
    }

    @Test func analyzerDetectsAnEarlyBeatFromTheCanonicalWaveform() throws {
        let report = PrematureBeatAnalyzer().analyze(makeSyntheticSignal(hasEarlyBeat: true))

        #expect(report.status == .analyzed)
        #expect(report.reason == nil)
        #expect(report.inputFormat == ECGSignal.formatIdentifier)
        #expect(report.summary.rPeakCount >= 13)
        #expect(report.summary.prematureCandidateCount == 1)
        let candidate = try #require(
            report.beats.first { $0.classification == .prematureUncertain }
        )
        #expect(abs(candidate.timeSeconds - 6.2) < 0.04)
        #expect(abs((candidate.prematurityRatio ?? 0) - 0.7) < 0.06)
    }

    @Test func analyzerRunsTheSamePathForARegularWaveform() {
        let report = PrematureBeatAnalyzer().analyze(makeSyntheticSignal(hasEarlyBeat: false))

        #expect(report.status == .analyzed)
        #expect(report.summary.prematureCandidateCount == 0)
    }

    @Test func analyzerRefusesMissingVoltageWithoutMovingSamples() {
        var signal = makeSyntheticSignal(hasEarlyBeat: true)
        var voltage = signal.voltageMillivolts
        voltage[100] = nil
        signal = ECGSignal(
            timeSeconds: signal.timeSeconds,
            voltageMillivolts: voltage,
            nominalSamplingRateHz: signal.nominalSamplingRateHz
        )

        let report = PrematureBeatAnalyzer().analyze(signal)

        #expect(report.status == .notAnalyzed)
        #expect(report.reason == .missingOrNonFiniteSamples)
        #expect(report.beats.isEmpty)
    }

    @Test func analyzerRefusesIrregularSamplingWithoutResampling() {
        let signal = makeSyntheticSignal(hasEarlyBeat: true)
        var times = signal.timeSeconds
        for index in 100..<times.count {
            times[index] += 1
        }
        let irregular = ECGSignal(
            timeSeconds: times,
            voltageMillivolts: signal.voltageMillivolts,
            nominalSamplingRateHz: signal.nominalSamplingRateHz
        )

        let report = PrematureBeatAnalyzer().analyze(irregular)

        #expect(report.status == .notAnalyzed)
        #expect(report.reason == .unsupportedSamplingOrDuration)
        #expect(report.beats.isEmpty)
    }

    @Test func detectorIsInsensitiveToAConstantVoltageOffset() {
        let signal = makeSyntheticSignal(hasEarlyBeat: true)
        let shifted = ECGSignal(
            timeSeconds: signal.timeSeconds,
            voltageMillivolts: signal.voltageMillivolts.map { $0.map { $0 + 0.8 } },
            nominalSamplingRateHz: signal.nominalSamplingRateHz
        )

        let original = PrematureBeatAnalyzer().analyze(signal)
        let offset = PrematureBeatAnalyzer().analyze(shifted)

        #expect(offset.beats.map(\.sampleIndex) == original.beats.map(\.sampleIndex))
        #expect(offset.summary == original.summary)
    }

    private func makeSyntheticSignal(hasEarlyBeat: Bool) -> ECGSignal {
        let samplingFrequencyHz = 250.0
        let sampleCount = Int(15 * samplingFrequencyHz)
        let times = (0..<sampleCount).map { Double($0) / samplingFrequencyHz }
        var voltages = Array(repeating: 0.0, count: sampleCount)
        var beatTimes = [0.5, 1.5, 2.5, 3.5, 4.5, 5.5, hasEarlyBeat ? 6.2 : 6.5]
        beatTimes += [7.5, 8.5, 9.5, 10.5, 11.5, 12.5, 13.5]

        for beatTime in beatTimes {
            let center = Int((beatTime * samplingFrequencyHz).rounded())
            for offset in -5...5 {
                let index = center + offset
                guard voltages.indices.contains(index) else { continue }
                voltages[index] += max(0, 1 - Double(abs(offset)) / 6)
            }
        }
        return ECGSignal(
            timeSeconds: times,
            voltageMillivolts: voltages.map { Optional.some($0) },
            nominalSamplingRateHz: samplingFrequencyHz
        )
    }
}
