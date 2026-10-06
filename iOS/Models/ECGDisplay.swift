import ECGCore
import Foundation

/// One sample selected for drawing. `sourceIndex` and `timeSeconds` always refer to the original
/// full-resolution signal; display downsampling never creates interpolated ECG values.
public struct ECGDisplaySample: Equatable, Sendable {
    public let sourceIndex: Int
    public let timeSeconds: Double
    public let voltageMillivolts: Double?

    public init(sourceIndex: Int, timeSeconds: Double, voltageMillivolts: Double?) {
        self.sourceIndex = sourceIndex
        self.timeSeconds = timeSeconds
        self.voltageMillivolts = voltageMillivolts
    }
}

/// A future detector can pass markers to the waveform without converting them to screen pixels.
/// Marker placement is always derived from its real signal timestamp.
public struct ECGWaveformMarker: Identifiable, Equatable, Sendable {
    /// Label the detail page gives to beats the model reports as `prematureUncertain`.
    public static let prematureCandidateLabel = "Early"

    public let id: String
    public let timeSeconds: Double
    public let label: String
    /// Original signal index of the model R peak, when the marker comes from a report beat.
    public let sampleIndex: Int?

    public init(id: String, timeSeconds: Double, label: String, sampleIndex: Int? = nil) {
        self.id = id
        self.timeSeconds = timeSeconds
        self.label = label
        self.sampleIndex = sampleIndex
    }

    public var isPrematureCandidate: Bool {
        label == Self.prematureCandidateLabel
    }
}

public struct ECGPeakInterval: Equatable, Sendable {
    public let startMarkerID: String
    public let endMarkerID: String
    public let startTimeSeconds: Double
    public let endTimeSeconds: Double
    public let durationMilliseconds: Double

    public init(
        startMarkerID: String,
        endMarkerID: String,
        startTimeSeconds: Double,
        endTimeSeconds: Double,
        durationMilliseconds: Double
    ) {
        self.startMarkerID = startMarkerID
        self.endMarkerID = endMarkerID
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.durationMilliseconds = durationMilliseconds
    }
}

/// Builds display-only R–R intervals from already-established markers. It does not detect peaks.
public enum ECGPeakIntervalBuilder {
    public static func intervals(between markers: [ECGWaveformMarker]) -> [ECGPeakInterval] {
        guard markers.count >= 2 else { return [] }
        var intervals: [ECGPeakInterval] = []
        intervals.reserveCapacity(markers.count - 1)

        for index in 1..<markers.count {
            let previous = markers[index - 1]
            let current = markers[index]
            guard previous.timeSeconds.isFinite,
                  current.timeSeconds.isFinite,
                  current.timeSeconds > previous.timeSeconds else {
                continue
            }
            intervals.append(
                ECGPeakInterval(
                    startMarkerID: previous.id,
                    endMarkerID: current.id,
                    startTimeSeconds: previous.timeSeconds,
                    endTimeSeconds: current.timeSeconds,
                    durationMilliseconds: (current.timeSeconds - previous.timeSeconds) * 1_000
                )
            )
        }
        return intervals
    }
}

public enum ECGTimeline {
    /// Maps a real timestamp to a clamped 0...1 drawing position.
    public static func normalizedPosition(
        for timeSeconds: Double,
        startTimeSeconds: Double,
        endTimeSeconds: Double
    ) -> Double? {
        guard timeSeconds.isFinite,
              startTimeSeconds.isFinite,
              endTimeSeconds.isFinite,
              endTimeSeconds > startTimeSeconds else {
            return nil
        }

        let position = (timeSeconds - startTimeSeconds) / (endTimeSeconds - startTimeSeconds)
        return min(max(position, 0), 1)
    }

    /// Produces stable 1/2/5-based labels for a horizontally scrollable time axis. The number of
    /// ticks is capped so long recordings cannot overload Canvas even at high zoom.
    public static func majorTickTimes(
        startTimeSeconds: Double,
        endTimeSeconds: Double,
        chartWidthPoints: Double,
        minimumSpacingPoints: Double = 64,
        maximumTickCount: Int = 100
    ) -> [Double] {
        guard startTimeSeconds.isFinite,
              endTimeSeconds.isFinite,
              endTimeSeconds > startTimeSeconds,
              chartWidthPoints.isFinite,
              chartWidthPoints > 0,
              minimumSpacingPoints.isFinite,
              minimumSpacingPoints > 0,
              maximumTickCount > 0 else {
            return []
        }

        let duration = endTimeSeconds - startTimeSeconds
        let maximumIntervalCount = max(1, maximumTickCount - 1)
        let visibleIntervalCount = min(
            Double(maximumIntervalCount),
            floor(chartWidthPoints / minimumSpacingPoints)
        )
        let intervalCapacity = max(1, Int(visibleIntervalCount))
        let interval = niceInterval(atLeast: duration / Double(intervalCapacity))
        guard interval.isFinite, interval > 0 else { return [] }

        let tolerance = interval * 1e-9
        let firstMultiple = ceil((startTimeSeconds - tolerance) / interval)
        let firstTick = firstMultiple * interval
        var ticks: [Double] = []
        ticks.reserveCapacity(min(maximumTickCount, intervalCapacity + 1))

        for index in 0..<maximumTickCount {
            var tick = firstTick + Double(index) * interval
            guard tick <= endTimeSeconds + tolerance else { break }
            if abs(tick) < tolerance { tick = 0 }
            ticks.append(tick)
        }
        return ticks
    }

    private static func niceInterval(atLeast rawInterval: Double) -> Double {
        let magnitude = pow(10, floor(log10(rawInterval)))
        let normalized = rawInterval / magnitude
        let multiplier: Double
        if normalized <= 1 {
            multiplier = 1
        } else if normalized <= 2 {
            multiplier = 2
        } else if normalized <= 5 {
            multiplier = 5
        } else {
            multiplier = 10
        }
        return multiplier * magnitude
    }
}

/// Millivolt gridlines for the waveform's vertical axis, using the same 1/2/5 steps as time.
public enum ECGVoltageAxis {
    public static func majorTicks(
        lowerMillivolts: Double,
        upperMillivolts: Double,
        chartHeightPoints: Double,
        minimumSpacingPoints: Double = 30
    ) -> [Double] {
        ECGTimeline.majorTickTimes(
            startTimeSeconds: lowerMillivolts,
            endTimeSeconds: upperMillivolts,
            chartWidthPoints: chartHeightPoints,
            minimumSpacingPoints: minimumSpacingPoints,
            maximumTickCount: 60
        )
    }
}

public enum ECGExtremumKind: Sendable {
    case maximum
    case minimum
}

/// Read-only lookups used by the on-screen measurement tool. They address original samples and
/// never interpolate a voltage that the source did not provide.
public enum ECGSignalLookup {
    /// Index of the timestamp closest to `timeSeconds`, assuming increasing timestamps.
    public static func nearestSampleIndex(to timeSeconds: Double, in times: [Double]) -> Int? {
        guard timeSeconds.isFinite, !times.isEmpty else { return nil }
        var lower = times.startIndex
        var upper = times.endIndex - 1
        while lower < upper {
            let middle = (lower + upper) / 2
            if times[middle] < timeSeconds {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        if lower > times.startIndex,
           abs(times[lower - 1] - timeSeconds) <= abs(times[lower] - timeSeconds) {
            return lower - 1
        }
        return lower
    }

    /// Index of the largest or smallest finite voltage within ±`radiusSeconds` of `index`.
    public static func localExtremumIndex(
        in signal: ECGSignal,
        around index: Int,
        radiusSeconds: Double,
        kind: ECGExtremumKind
    ) -> Int? {
        let times = signal.timeSeconds
        let voltages = signal.voltageMillivolts
        guard times.count == voltages.count,
              times.indices.contains(index),
              times[index].isFinite,
              radiusSeconds.isFinite,
              radiusSeconds >= 0 else {
            return nil
        }

        let centerTime = times[index]
        var best: (index: Int, value: Double)?
        func consider(_ candidate: Int) {
            guard let value = voltages[candidate], value.isFinite else { return }
            let isBetter: Bool
            switch kind {
            case .maximum: isBetter = best.map { value > $0.value } ?? true
            case .minimum: isBetter = best.map { value < $0.value } ?? true
            }
            if isBetter { best = (candidate, value) }
        }

        var cursor = index
        while cursor >= times.startIndex, abs(times[cursor] - centerTime) <= radiusSeconds {
            consider(cursor)
            cursor -= 1
        }
        cursor = index + 1
        while cursor < times.endIndex, abs(times[cursor] - centerTime) <= radiusSeconds {
            consider(cursor)
            cursor += 1
        }
        return best?.index
    }
}

/// The difference between two caliper points, always expressed as B − A.
public struct ECGCaliperReading: Equatable, Sendable {
    /// Δt range for which "one cardiac cycle" rate conversion is shown (20–240 BPM).
    public static let cycleRateRangeMilliseconds = 250.0...3_000.0

    public let deltaTimeMilliseconds: Double
    public let deltaVoltageMillivolts: Double

    public init(
        timeASeconds: Double,
        voltageAMillivolts: Double,
        timeBSeconds: Double,
        voltageBMillivolts: Double
    ) {
        self.deltaTimeMilliseconds = (timeBSeconds - timeASeconds) * 1_000
        self.deltaVoltageMillivolts = voltageBMillivolts - voltageAMillivolts
    }

    /// 60,000 / |Δt|, only when Δt could plausibly be one beat-to-beat cycle.
    public var equivalentRateBPM: Double? {
        let magnitude = abs(deltaTimeMilliseconds)
        guard Self.cycleRateRangeMilliseconds.contains(magnitude) else { return nil }
        return 60_000 / magnitude
    }
}

/// Reduces only the copy used for drawing. The `ECGSignal` retained by `ECGMeasurement` remains
/// full resolution for analysis and raw export.
public enum ECGDisplayDownsampler {
    public static func samples(
        from signal: ECGSignal,
        maximumPointCount: Int
    ) -> [ECGDisplaySample] {
        let sampleCount = signal.timeSeconds.count
        guard sampleCount == signal.voltageMillivolts.count,
              sampleCount > 0,
              maximumPointCount > 0 else {
            return []
        }

        func sample(at index: Int) -> ECGDisplaySample {
            ECGDisplaySample(
                sourceIndex: index,
                timeSeconds: signal.timeSeconds[index],
                voltageMillivolts: signal.voltageMillivolts[index]
            )
        }

        if sampleCount <= maximumPointCount {
            return signal.timeSeconds.indices.map { sample(at: $0) }
        }
        if maximumPointCount == 1 {
            return [sample(at: signal.timeSeconds.startIndex)]
        }
        if maximumPointCount == 2 {
            return [sample(at: signal.timeSeconds.startIndex), sample(at: sampleCount - 1)]
        }

        let interiorCount = sampleCount - 2
        let interiorCapacity = maximumPointCount - 2
        let bucketCount = max(1, (interiorCapacity + 1) / 2)
        var selected: [ECGDisplaySample] = [sample(at: 0)]
        selected.reserveCapacity(maximumPointCount)

        for bucket in 0..<bucketCount {
            let lower = 1 + (bucket * interiorCount) / bucketCount
            let upper = 1 + ((bucket + 1) * interiorCount) / bucketCount
            guard lower < upper else { continue }

            let remainingBuckets = bucketCount - bucket
            let remainingCapacity = interiorCapacity - (selected.count - 1)
            let slotCount = max(1, remainingCapacity / remainingBuckets)
            let candidateIndices = selectedIndices(
                in: lower..<upper,
                voltageMillivolts: signal.voltageMillivolts,
                slotCount: slotCount
            )
            selected.append(contentsOf: candidateIndices.map { sample(at: $0) })
        }

        selected.append(sample(at: sampleCount - 1))
        return Array(selected.prefix(maximumPointCount))
    }

    /// Selects original extrema for an envelope. If a bucket contains a missing/non-finite value,
    /// one such point is preferred so the rendered path keeps a visible break rather than joining
    /// across data that HealthKit did not provide.
    private static func selectedIndices(
        in indices: Range<Int>,
        voltageMillivolts: [Double?],
        slotCount: Int
    ) -> [Int] {
        guard slotCount > 0 else { return [] }

        var gapIndex: Int?
        var minimumIndex: Int?
        var maximumIndex: Int?

        for index in indices {
            guard let voltage = voltageMillivolts[index], voltage.isFinite else {
                if gapIndex == nil { gapIndex = index }
                continue
            }

            if let currentMinimumIndex = minimumIndex,
               let currentMinimum = voltageMillivolts[currentMinimumIndex] {
                if voltage < currentMinimum { minimumIndex = index }
            } else {
                minimumIndex = index
            }
            if let currentMaximumIndex = maximumIndex,
               let currentMaximum = voltageMillivolts[currentMaximumIndex] {
                if voltage > currentMaximum { maximumIndex = index }
            } else {
                maximumIndex = index
            }
        }

        var result: [Int] = []
        if let gapIndex {
            result.append(gapIndex)
        }

        let finiteExtrema = [minimumIndex, maximumIndex]
            .compactMap { $0 }
            .filter { !result.contains($0) }

        if result.isEmpty, slotCount == 1, let minimumIndex, let maximumIndex {
            let minimumMagnitude = abs(voltageMillivolts[minimumIndex] ?? 0)
            let maximumMagnitude = abs(voltageMillivolts[maximumIndex] ?? 0)
            result.append(minimumMagnitude > maximumMagnitude ? minimumIndex : maximumIndex)
        } else {
            result.append(contentsOf: finiteExtrema)
        }

        return Array(result.prefix(slotCount)).sorted()
    }
}
