import Foundation

/// Internal dependency-free detector used by the v1 vertical slice.
enum GradientEnergyRPeakDetector {
    static func detect(
        voltageMillivolts: [Double],
        samplingFrequencyHz: Double,
        lowCutoffHz: Double,
        highCutoffHz: Double,
        refractoryPeriodMilliseconds: Double,
        refinementRadiusMilliseconds: Double
    ) -> [Int] {
        guard voltageMillivolts.count >= 3,
              samplingFrequencyHz.isFinite,
              samplingFrequencyHz > 50,
              lowCutoffHz > 0,
              highCutoffHz > lowCutoffHz,
              highCutoffHz < samplingFrequencyHz / 2 else {
            return []
        }

        let highPass = Biquad.highPass(
            cutoffHz: lowCutoffHz,
            samplingFrequencyHz: samplingFrequencyHz
        )
        let lowPass = Biquad.lowPass(
            cutoffHz: highCutoffHz,
            samplingFrequencyHz: samplingFrequencyHz
        )
        // One second of odd-symmetric padding absorbs the filter start-up transient, so a DC
        // offset or a step at either edge does not become a spurious first/last peak.
        let paddingSamples = max(1, Int(samplingFrequencyHz.rounded()))
        var filtered = zeroPhaseFilter(
            voltageMillivolts,
            coefficients: highPass,
            paddingSamples: paddingSamples
        )
        filtered = zeroPhaseFilter(filtered, coefficients: lowPass, paddingSamples: paddingSamples)

        var energy = Array(repeating: 0.0, count: filtered.count)
        for index in 1..<filtered.count {
            let slope = filtered[index] - filtered[index - 1]
            energy[index] = slope * slope
        }
        let integrationSamples = max(1, Int((0.12 * samplingFrequencyHz).rounded()))
        let integrated = movingAverage(energy, windowSize: integrationSamples)
        let refractorySamples = max(
            1,
            Int((refractoryPeriodMilliseconds * samplingFrequencyHz / 1_000).rounded())
        )
        let refinementSamples = max(
            1,
            Int((refinementRadiusMilliseconds * samplingFrequencyHz / 1_000).rounded())
        )
        let chunkSamples = max(1, Int((30 * samplingFrequencyHz).rounded()))
        var energyCandidates: [Int] = []

        var chunkStart = 0
        while chunkStart < integrated.count {
            var chunkEnd = min(chunkStart + chunkSamples, integrated.count)
            // Fold a short remainder into this chunk instead of thresholding a few samples alone.
            if integrated.count - chunkEnd < chunkSamples / 2 {
                chunkEnd = integrated.count
            }
            let chunk = Array(integrated[chunkStart..<chunkEnd])
            guard let background = median(chunk),
                  let percentile95 = percentile(chunk, fraction: 0.95) else {
                chunkStart = chunkEnd
                continue
            }
            let mad = median(chunk.map { abs($0 - background) }) ?? 0
            let threshold = max(background + 4 * mad, percentile95 * 0.25)
            if threshold > 0, threshold.isFinite, chunkEnd - chunkStart >= 3 {
                appendCandidates(
                    from: integrated,
                    chunkRange: chunkStart..<chunkEnd,
                    threshold: threshold,
                    prominenceRadius: refinementSamples,
                    refractorySamples: refractorySamples,
                    to: &energyCandidates
                )
            }
            chunkStart = chunkEnd
        }

        return refine(
            energyCandidates,
            filtered: filtered,
            refinementSamples: refinementSamples,
            refractorySamples: refractorySamples
        )
    }

    private static func appendCandidates(
        from integrated: [Double],
        chunkRange: Range<Int>,
        threshold: Double,
        prominenceRadius: Int,
        refractorySamples: Int,
        to candidates: inout [Int]
    ) {
        let lower = max(1, chunkRange.lowerBound)
        let upper = min(integrated.count - 2, chunkRange.upperBound - 1)
        guard lower <= upper else { return }

        for index in lower...upper {
            let value = integrated[index]
            guard value >= threshold,
                  value >= integrated[index - 1],
                  value > integrated[index + 1] else {
                continue
            }
            let left = integrated[max(0, index - prominenceRadius)...index].min() ?? value
            let rightBoundary = min(integrated.count - 1, index + prominenceRadius)
            let right = integrated[index...rightBoundary].min() ?? value
            guard value - max(left, right) >= threshold * 0.5 else { continue }

            if let previous = candidates.last, index - previous < refractorySamples {
                if value > integrated[previous] {
                    candidates[candidates.count - 1] = index
                }
            } else {
                candidates.append(index)
            }
        }
    }

    private static func refine(
        _ candidates: [Int],
        filtered: [Double],
        refinementSamples: Int,
        refractorySamples: Int
    ) -> [Int] {
        var refined: [Int] = []
        for candidate in candidates {
            let lower = max(0, candidate - refinementSamples)
            let upper = min(filtered.count - 1, candidate + refinementSamples)
            var peakIndex = lower
            var peakMagnitude = abs(filtered[lower])
            if lower < upper {
                for index in (lower + 1)...upper {
                    let magnitude = abs(filtered[index])
                    if magnitude > peakMagnitude {
                        peakMagnitude = magnitude
                        peakIndex = index
                    }
                }
            }

            if let previous = refined.last, peakIndex - previous < refractorySamples {
                // Replacing must not move the peak into the refractory period of the one before.
                let keepsOrder = refined.count < 2
                    || peakIndex - refined[refined.count - 2] >= refractorySamples
                if peakMagnitude > abs(filtered[previous]), keepsOrder {
                    refined[refined.count - 1] = peakIndex
                }
            } else if refined.last.map({ peakIndex > $0 }) ?? true {
                refined.append(peakIndex)
            }
        }
        return refined
    }

    /// Centered moving average, so the energy peak stays aligned with the QRS instead of lagging
    /// by half a window. The window is clipped (and the mean renormalized) at the edges.
    private static func movingAverage(_ values: [Double], windowSize: Int) -> [Double] {
        guard !values.isEmpty else { return [] }
        let window = max(1, windowSize)
        var prefixSums = Array(repeating: 0.0, count: values.count + 1)
        for index in values.indices {
            prefixSums[index + 1] = prefixSums[index] + values[index]
        }
        let halfWindow = window / 2
        var result = Array(repeating: 0.0, count: values.count)
        for index in values.indices {
            let lower = max(0, index - halfWindow)
            let upper = min(values.count, index - halfWindow + window)
            result[index] = (prefixSums[upper] - prefixSums[lower]) / Double(upper - lower)
        }
        return result
    }

    private static func zeroPhaseFilter(
        _ values: [Double],
        coefficients: Biquad,
        paddingSamples: Int
    ) -> [Double] {
        let padding = min(paddingSamples, values.count - 1)
        guard padding > 0 else {
            let forward = coefficients.apply(to: values)
            return Array(coefficients.apply(to: Array(forward.reversed())).reversed())
        }

        let first = values[0]
        let last = values[values.count - 1]
        var extended: [Double] = []
        extended.reserveCapacity(values.count + 2 * padding)
        for offset in stride(from: padding, through: 1, by: -1) {
            extended.append(2 * first - values[offset])
        }
        extended.append(contentsOf: values)
        for offset in 1...padding {
            extended.append(2 * last - values[values.count - 1 - offset])
        }

        let forward = coefficients.apply(to: extended)
        let backward = Array(coefficients.apply(to: Array(forward.reversed())).reversed())
        return Array(backward[padding..<(padding + values.count)])
    }

    private static func median(_ values: [Double]) -> Double? {
        percentile(values, fraction: 0.5)
    }

    private static func percentile(_ values: [Double], fraction: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let bounded = min(max(fraction, 0), 1)
        let index = Int((Double(sorted.count - 1) * bounded).rounded())
        return sorted[index]
    }
}

private struct Biquad {
    let b0: Double
    let b1: Double
    let b2: Double
    let a1: Double
    let a2: Double

    static func lowPass(cutoffHz: Double, samplingFrequencyHz: Double) -> Biquad {
        make(cutoffHz: cutoffHz, samplingFrequencyHz: samplingFrequencyHz, highPass: false)
    }

    static func highPass(cutoffHz: Double, samplingFrequencyHz: Double) -> Biquad {
        make(cutoffHz: cutoffHz, samplingFrequencyHz: samplingFrequencyHz, highPass: true)
    }

    func apply(to values: [Double]) -> [Double] {
        var result = Array(repeating: 0.0, count: values.count)
        var x1 = 0.0
        var x2 = 0.0
        var y1 = 0.0
        var y2 = 0.0
        for index in values.indices {
            let x0 = values[index]
            let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            result[index] = y0
            x2 = x1
            x1 = x0
            y2 = y1
            y1 = y0
        }
        return result
    }

    private static func make(
        cutoffHz: Double,
        samplingFrequencyHz: Double,
        highPass: Bool
    ) -> Biquad {
        let omega = 2 * Double.pi * cutoffHz / samplingFrequencyHz
        let cosine = cos(omega)
        let sine = sin(omega)
        let alpha = sine / (2 * sqrt(0.5))
        let a0 = 1 + alpha
        let rawB0 = highPass ? (1 + cosine) / 2 : (1 - cosine) / 2
        let rawB1 = highPass ? -(1 + cosine) : 1 - cosine
        let rawB2 = rawB0
        return Biquad(
            b0: rawB0 / a0,
            b1: rawB1 / a0,
            b2: rawB2 / a0,
            a1: (-2 * cosine) / a0,
            a2: (1 - alpha) / a0
        )
    }
}
