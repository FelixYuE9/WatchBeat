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
    public let id: String
    public let timeSeconds: Double
    public let label: String

    public init(id: String, timeSeconds: Double, label: String) {
        self.id = id
        self.timeSeconds = timeSeconds
        self.label = label
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
