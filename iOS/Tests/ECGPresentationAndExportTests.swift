// See ECGHealthKitMapperTests.swift: HealthKit re-exports the Foundation types used here.
import ECGCore
import HealthKit
import Testing
import WatchBeatModels

@Suite struct ECGPresentationAndExportTests {
    @Test func displayDownsamplingKeepsSourceSignalAndExtrema() {
        let signal = ECGSignal(
            timeSeconds: (0..<100).map { Double($0) },
            voltageMillivolts: (0..<100).map { index in
                if index == 40 { return -9.0 }
                if index == 60 { return 12.0 }
                return Double(index % 5)
            },
            nominalSamplingRateHz: 1
        )
        let originalTimes = signal.timeSeconds
        let originalVoltages = signal.voltageMillivolts

        let display = ECGDisplayDownsampler.samples(from: signal, maximumPointCount: 20)

        #expect(display.count <= 20)
        #expect(display.first?.sourceIndex == 0)
        #expect(display.last?.sourceIndex == 99)
        #expect(display.map(\.sourceIndex) == display.map(\.sourceIndex).sorted())
        #expect(display.contains { $0.voltageMillivolts == -9.0 })
        #expect(display.contains { $0.voltageMillivolts == 12.0 })
        #expect(signal.timeSeconds == originalTimes)
        #expect(signal.voltageMillivolts == originalVoltages)
    }

    @Test func displayDownsamplingRetainsMissingValueAsGap() {
        var voltages = Array(repeating: Double?.some(0.2), count: 50)
        voltages[25] = nil
        let signal = ECGSignal(
            timeSeconds: (0..<50).map { Double($0) * 0.002 },
            voltageMillivolts: voltages,
            nominalSamplingRateHz: 500
        )

        let display = ECGDisplayDownsampler.samples(from: signal, maximumPointCount: 12)

        #expect(display.contains { $0.sourceIndex == 25 && $0.voltageMillivolts == nil })
    }

    @Test func timelineUsesRealTimestampAndClampsOutsideRange() {
        #expect(
            ECGTimeline.normalizedPosition(
                for: 12.5,
                startTimeSeconds: 10,
                endTimeSeconds: 20
            ) == 0.25
        )
        #expect(
            ECGTimeline.normalizedPosition(
                for: 25,
                startTimeSeconds: 10,
                endTimeSeconds: 20
            ) == 1
        )
        #expect(
            ECGTimeline.normalizedPosition(
                for: 10,
                startTimeSeconds: 10,
                endTimeSeconds: 10
            ) == nil
        )
    }

    @Test func timelineBuildsReadableSecondTicksForScrollableWaveform() {
        let ticks = ECGTimeline.majorTickTimes(
            startTimeSeconds: 0,
            endTimeSeconds: 30,
            chartWidthPoints: 2_520
        )

        #expect(ticks.first == 0)
        #expect(ticks.contains(12))
        #expect(ticks.last == 30)
        #expect(ticks.count <= 100)
        #expect(zip(ticks, ticks.dropFirst()).allSatisfy { pair in pair.0 < pair.1 })
    }

    @Test func overviewViewportMapsScrollingAndArbitraryTimestamps() throws {
        let initial = try #require(ECGWaveformViewport(
            timeRange: 10...40,
            contentWidthPoints: 3_000,
            viewportWidthPoints: 300,
            offsetPoints: 0
        ))
        #expect(initial.visibleTimeRange == 10...13)

        // A timestamp need not coincide with a detected beat or an integer second.
        let targetTime = 29.125
        let navigated = try #require(ECGWaveformViewport(
            timeRange: initial.timeRange,
            contentWidthPoints: initial.contentWidthPoints,
            viewportWidthPoints: initial.viewportWidthPoints,
            offsetPoints: initial.offsetPoints(centering: targetTime)
        ))
        #expect(abs(navigated.centerTimeSeconds - targetTime) < 1e-9)
        #expect(abs(navigated.visibleTimeRange.lowerBound - 27.625) < 1e-9)
        #expect(abs(navigated.visibleTimeRange.upperBound - 30.625) < 1e-9)

        let manuallyScrolled = try #require(ECGWaveformViewport(
            timeRange: initial.timeRange,
            contentWidthPoints: 3_000,
            viewportWidthPoints: 300,
            offsetPoints: 1_200
        ))
        #expect(manuallyScrolled.visibleTimeRange == 22...25)
    }

    @Test func overviewViewportKeepsFirstAndLastWindowsInsideRecording() throws {
        let viewport = try #require(ECGWaveformViewport(
            timeRange: 0...30,
            contentWidthPoints: 3_000,
            viewportWidthPoints: 300,
            offsetPoints: -50
        ))
        #expect(viewport.visibleTimeRange == 0...3)
        #expect(viewport.offsetPoints(centering: -1) == 0)
        #expect(viewport.offsetPoints(centering: 0) == 0)
        #expect(viewport.offsetPoints(centering: 30) == 2_700)
        #expect(viewport.offsetPoints(centering: 99) == 2_700)

        let last = try #require(ECGWaveformViewport(
            timeRange: 0...30,
            contentWidthPoints: 3_000,
            viewportWidthPoints: 300,
            offsetPoints: 4_000
        ))
        #expect(last.visibleTimeRange == 27...30)
        #expect(last.offsetPoints(centering: .nan) == last.offsetPoints)
    }

    @Test func overviewViewportShrinksWindowWithoutLosingTimeWhenZooming() throws {
        let zoomed = try #require(ECGWaveformViewport(
            timeRange: 0...30,
            contentWidthPoints: 24_000,
            viewportWidthPoints: 300,
            offsetPoints: 0
        ))
        let located = try #require(ECGWaveformViewport(
            timeRange: zoomed.timeRange,
            contentWidthPoints: zoomed.contentWidthPoints,
            viewportWidthPoints: zoomed.viewportWidthPoints,
            offsetPoints: zoomed.offsetPoints(centering: 19)
        ))
        #expect(abs(located.centerTimeSeconds - 19) < 1e-9)
        #expect(abs(located.visibleTimeRange.lowerBound - 18.8125) < 1e-9)
        #expect(abs(located.visibleTimeRange.upperBound - 19.1875) < 1e-9)
    }

    @Test func overviewViewportHandlesShortRecordingsAndRejectsInvalidGeometry() throws {
        let short = try #require(ECGWaveformViewport(
            timeRange: 0...1,
            contentWidthPoints: 100,
            viewportWidthPoints: 300,
            offsetPoints: 50
        ))
        #expect(short.visibleTimeRange == 0...1)
        #expect(short.offsetPoints(centering: 0.8) == 0)

        #expect(ECGWaveformViewport(
            timeRange: 0...0, contentWidthPoints: 100, viewportWidthPoints: 50, offsetPoints: 0
        ) == nil)
        #expect(ECGWaveformViewport(
            timeRange: 0...30, contentWidthPoints: 0, viewportWidthPoints: 50, offsetPoints: 0
        ) == nil)
        #expect(ECGWaveformViewport(
            timeRange: 0...30, contentWidthPoints: 100, viewportWidthPoints: .infinity, offsetPoints: 0
        ) == nil)
        #expect(ECGWaveformViewport(
            timeRange: 0...30, contentWidthPoints: 100, viewportWidthPoints: 50, offsetPoints: .nan
        ) == nil)
    }

    @Test func rawCSVPreservesOrderTimestampsAndMissingVoltage() throws {
        let measurement = try makeMeasurement(
            times: [0.004, 0.000, 0.002],
            voltages: [1.25, nil, -0.5],
            issues: [.missingLeadVoltage, .nonIncreasingTimeOrder]
        )

        let data = try ECGExportEncoder.rawCSV(for: measurement)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(
            text == """
            time_s,voltage_mV
            0.004,1.25
            0.0,
            0.002,-0.5

            """
        )
    }

    @Test func metadataJSONContainsFactsButNotHealthKitIdentifier() throws {
        let measurement = try makeMeasurement(
            times: [0, 0.002, 0.004],
            voltages: [0.1, nil, 0.3],
            issues: [.missingLeadVoltage]
        )

        let data = try ECGExportEncoder.metadataJSON(for: measurement)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("\"format\" : \"watchbeat.ecg.metadata\""))
        #expect(text.contains("\"schemaVersion\" : 1"))
        #expect(text.contains("\"dataSource\" : \"healthKit\""))
        #expect(text.contains("\"missingLeadVoltage\""))
        #expect(text.contains("\"missingVoltageIndices\" : ["))
        #expect(!text.contains(measurement.record.id.uuidString))
    }

    @Test func builtInExampleIsDeterministicAndExplicitlySynthetic() throws {
        let first = try ECGExampleFactory.makeMeasurement()
        let second = try ECGExampleFactory.makeMeasurement()

        #expect(first.source == .builtInSyntheticExample)
        #expect(first.signal == second.signal)
        #expect(first.signal.timeSeconds.count == 15_000)
        #expect(first.integrity.sampleCount == 15_000)
        #expect(first.isComplete)
        #expect(first.analysis.status == .analyzed)
        #expect(first.analysis.inputFormat == ECGSignal.formatIdentifier)
        #expect(first.analysis.summary.rPeakCount > 30)

        let metadata = try ECGExportEncoder.metadataJSON(for: first)
        let text = try #require(String(data: metadata, encoding: .utf8))
        #expect(text.contains("\"dataSource\" : \"builtInSyntheticExample\""))
        #expect(!text.contains("\"classification\""))
        #expect(!text.contains("\"startDate\""))
    }

    @Test func analysisExportUsesTheVersionedOutputContractAndOmitsHealthKitID() throws {
        let measurement = try ECGExampleFactory.makeMeasurement()
        let data = try ECGExportEncoder.analysisJSON(for: measurement)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("\"schemaVersion\" : 1"))
        #expect(text.contains("\"inputFormat\" : \"watchbeat.ecg.signal.v1\""))
        #expect(text.contains("\"status\" : \"analyzed\""))
        #expect(text.contains("\"researchOnly\" : true"))
        #expect(text.contains("\"detectorIdentifier\" : \"watchbeat-gradient-energy-rr-v1\""))
        #expect(text.contains("\"prematurityThreshold\" : 0.8"))
        #expect(text.contains("\"rrVariability\" : {"))
        #expect(text.contains("\"metricsVersion\" : \"watchbeat.rr-variability.v1\""))
        #expect(text.contains("\"coefficientOfVariationPercent\""))
        #expect(text.contains("\"candidateAdjacentIntervalCount\""))
        #expect(text.contains("\"rhythmMetrics\" : {"))
        #expect(text.contains("\"metricsVersion\" : \"watchbeat.rr-summary.v1\""))
        #expect(text.contains("\"medianDetectedHeartRateBPM\""))
        #expect(text.contains("\"rrInterquartileRangeMilliseconds\""))
        #expect(!text.contains(measurement.record.id.uuidString))
    }

    @Test func builtInExampleShowsModelDetectedPrematureCandidates() throws {
        let measurement = try ECGExampleFactory.makeMeasurement()
        let report = measurement.analysis

        #expect(report.status == .analyzed)
        #expect(report.summary.rPeakCount == 35)
        #expect(report.summary.prematureCandidateCount == 2)
        #expect(measurement.screeningSummary == .prematureCandidates(count: 2))
        #expect(measurement.analysisDurationSeconds >= 0)

        let intervals = ECGPeakIntervalBuilder.intervals(
            between: report.beats.map {
                ECGWaveformMarker(id: "\($0.sampleIndex)", timeSeconds: $0.timeSeconds, label: "R")
            }
        )
        #expect(intervals.count == report.beats.count - 1)
    }

    @Test func builtInExampleReportsDescriptiveRRAndAmplitudeValues() throws {
        let report = try ECGExampleFactory.makeMeasurement().analysis
        let descriptors = try #require(report.recordingDescriptors)
        let beatPeriod = ECGExampleFactory.beatPeriodSeconds * 1_000

        // Generator: coupling 0.62 × period; the PVC-like beat has a fully compensatory pause.
        #expect(abs(descriptors.shortestRRMilliseconds - 0.62 * beatPeriod) < 10)
        #expect(abs(descriptors.longestRRMilliseconds - 1.38 * beatPeriod) < 10)
        #expect(descriptors.longRRIntervalCount == 0)
        #expect(descriptors.consecutiveCandidatePairCount == 0)
        let median = try #require(descriptors.medianQRSPeakToTroughMillivolts)
        let maximum = try #require(descriptors.maximumQRSPeakToTroughMillivolts)
        #expect((1.1...1.6).contains(median))
        // The wide PVC-like complex has the deepest trough in the example.
        #expect(maximum > median + 0.2)
        #expect(report.beats.allSatisfy { $0.qrsPeakToTroughMillivolts != nil })
    }

    @Test func waveformMarkersCarryCandidateFlagAndSampleIndex() {
        let candidate = ECGWaveformMarker(
            id: "c",
            timeSeconds: 1,
            label: ECGWaveformMarker.prematureCandidateLabel,
            sampleIndex: 500
        )
        let regular = ECGWaveformMarker(id: "r", timeSeconds: 2, label: "R")

        #expect(candidate.isPrematureCandidate)
        #expect(candidate.sampleIndex == 500)
        #expect(!regular.isPrematureCandidate)
        #expect(regular.sampleIndex == nil)
    }

    @Test func signalLookupFindsNearestSampleAndLocalExtrema() throws {
        let times = (0..<6).map { Double($0) * 0.002 }
        #expect(ECGSignalLookup.nearestSampleIndex(to: 0.0031, in: times) == 2)
        #expect(ECGSignalLookup.nearestSampleIndex(to: 0.0029, in: times) == 1)
        #expect(ECGSignalLookup.nearestSampleIndex(to: -1, in: times) == 0)
        #expect(ECGSignalLookup.nearestSampleIndex(to: 9, in: times) == 5)
        #expect(ECGSignalLookup.nearestSampleIndex(to: .nan, in: times) == nil)
        #expect(ECGSignalLookup.nearestSampleIndex(to: 0, in: []) == nil)

        let signal = ECGSignal(
            timeSeconds: times,
            voltageMillivolts: [0, 0.5, nil, 2.0, -1.0, 0.3],
            nominalSamplingRateHz: 500
        )
        #expect(
            ECGSignalLookup.localExtremumIndex(
                in: signal, around: 1, radiusSeconds: 0.0065, kind: .maximum
            ) == 3
        )
        #expect(
            ECGSignalLookup.localExtremumIndex(
                in: signal, around: 1, radiusSeconds: 0.0065, kind: .minimum
            ) == 4
        )
        // The window never reaches index 5 from index 1.
        #expect(
            ECGSignalLookup.localExtremumIndex(
                in: signal, around: 0, radiusSeconds: 0.001, kind: .maximum
            ) == 0
        )
    }

    @Test func caliperReadingIsBMinusAAndOnlyConvertsCycleLengthsToRate() throws {
        let cycle = ECGCaliperReading(
            timeASeconds: 1.0,
            voltageAMillivolts: 0.2,
            timeBSeconds: 1.8,
            voltageBMillivolts: -0.3
        )
        #expect(abs(cycle.deltaTimeMilliseconds - 800) < 0.000_1)
        #expect(abs(cycle.deltaVoltageMillivolts + 0.5) < 0.000_1)
        #expect(abs(try #require(cycle.equivalentRateBPM) - 75) < 0.001)

        let qrs = ECGCaliperReading(
            timeASeconds: 2.0,
            voltageAMillivolts: 1.1,
            timeBSeconds: 1.92,
            voltageBMillivolts: -0.2
        )
        #expect(abs(qrs.deltaTimeMilliseconds + 80) < 0.000_1)
        #expect(qrs.equivalentRateBPM == nil)
    }

    @Test func voltageAxisUsesReadableMillivoltSteps() {
        let ticks = ECGVoltageAxis.majorTicks(
            lowerMillivolts: -0.5,
            upperMillivolts: 1.5,
            chartHeightPoints: 180
        )

        #expect(ticks.contains(0))
        #expect(ticks.first == -0.5)
        #expect(ticks.last == 1.5)
        #expect(zip(ticks, ticks.dropFirst()).allSatisfy { abs(($0.1 - $0.0) - 0.5) < 1e-9 })
    }

    @Test func peakIntervalsSkipInvalidOrNonIncreasingMarkerPairs() {
        let markers = [
            ECGWaveformMarker(id: "a", timeSeconds: 1.0, label: "R"),
            ECGWaveformMarker(id: "b", timeSeconds: 0.5, label: "R"),
            ECGWaveformMarker(id: "c", timeSeconds: 2.0, label: "R"),
            ECGWaveformMarker(id: "d", timeSeconds: .nan, label: "R")
        ]

        let intervals = ECGPeakIntervalBuilder.intervals(between: markers)

        #expect(intervals.count == 1)
        #expect(intervals.first?.startMarkerID == "b")
        #expect(intervals.first?.endMarkerID == "c")
        #expect(intervals.first?.durationMilliseconds == 1_500)
    }

    @Test func rawCSVRejectsMismatchedArrays() throws {
        let record = makeRecord(declaredMeasurementCount: 1)
        let signal = ECGSignal(
            timeSeconds: [0, 0.002],
            voltageMillivolts: [0.1],
            nominalSamplingRateHz: 500
        )
        let integrity = ECGSignalIntegrityReport(
            sampleCount: 0,
            missingVoltageIndices: [],
            nonFiniteTimeIndices: [],
            nonFiniteVoltageIndices: [],
            duplicateTimestampIndices: [],
            decreasingTimestampIndices: [],
            medianSamplingIntervalSeconds: nil,
            inferredSamplingRateHz: nil,
            samplingIntervalRelativeMAD: nil
        )
        let measurement = ECGMeasurement(
            record: record,
            signal: signal,
            integrity: integrity,
            issues: [.integrityCheckFailed]
        )

        #expect(throws: ECGExportEncodingError.self) {
            try ECGExportEncoder.rawCSV(for: measurement)
        }
    }

    private func makeMeasurement(
        times: [Double],
        voltages: [Double?],
        issues: [ECGMeasurementIssue]
    ) throws -> ECGMeasurement {
        let signal = ECGSignal(
            timeSeconds: times,
            voltageMillivolts: voltages,
            nominalSamplingRateHz: 500
        )
        return ECGMeasurement(
            record: makeRecord(declaredMeasurementCount: times.count),
            signal: signal,
            integrity: try ECGSignalInspector.inspect(signal),
            issues: issues
        )
    }

    private func makeRecord(declaredMeasurementCount: Int) -> ECGRecord {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return ECGRecord(
            id: UUID(uuid: (
                0x57, 0x42, 0x45, 0x41, 0x54, 0x00, 0x40, 0x00,
                0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02
            )),
            startDate: start,
            endDate: start.addingTimeInterval(30),
            classification: .sinusRhythm,
            averageHeartRateBPM: 68,
            samplingFrequencyHz: 500,
            declaredMeasurementCount: declaredMeasurementCount,
            symptomsStatus: .none
        )
    }
}
