import ECGCore
import SwiftUI
import WatchBeatModels

/// A horizontally scrollable waveform. Drawing uses a timestamp-preserving display envelope;
/// `signal` itself remains full resolution for analysis and export.
public struct ECGWaveformView: View {
    private let signal: ECGSignal
    private let markers: [ECGWaveformMarker]
    @State private var zoom = 1.0

    public init(signal: ECGSignal, markers: [ECGWaveformMarker] = []) {
        self.signal = signal
        self.markers = markers
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Waveform")
                    .font(.headline)
                Spacer()
                Text("\(signal.timeSeconds.count) full-resolution samples")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let timeRange, let voltageRange {
                HStack(spacing: 10) {
                    Image(systemName: "minus.magnifyingglass")
                    Slider(value: $zoom, in: 1...8, step: 0.5)
                        .accessibilityLabel("Waveform zoom")
                    Image(systemName: "plus.magnifyingglass")
                    Text(String(format: "%.1f×", zoom))
                        .font(.caption.monospacedDigit())
                        .frame(width: 38, alignment: .trailing)
                }

                GeometryReader { geometry in
                    ScrollView(.horizontal) {
                        Canvas { context, size in
                            drawGrid(
                                context: &context,
                                size: size,
                                timeRange: timeRange,
                                voltageRange: voltageRange
                            )
                            drawSignal(
                                context: &context,
                                size: size,
                                timeRange: timeRange,
                                voltageRange: voltageRange
                            )
                            drawMarkers(
                                context: &context,
                                size: size,
                                timeRange: timeRange
                            )
                        }
                        .frame(
                            width: chartWidth(
                                minimumWidth: geometry.size.width,
                                duration: timeRange.upperBound - timeRange.lowerBound
                            ),
                            height: 220
                        )
                        .background(Color.secondary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .scrollIndicators(.visible)
                }
                .frame(height: 220)

                HStack {
                    Text(String(format: "%.2f s", timeRange.lowerBound))
                    Spacer()
                    Text("Scroll horizontally · timestamps are preserved")
                    Spacer()
                    Text(String(format: "%.2f s", timeRange.upperBound))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView(
                    "Waveform unavailable",
                    systemImage: "waveform.path.ecg",
                    description: Text("No finite timestamp and voltage pair can be drawn.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var timeRange: ClosedRange<Double>? {
        let finiteTimes = signal.timeSeconds.filter { $0.isFinite }
        guard let lower = finiteTimes.min(), let upper = finiteTimes.max() else { return nil }
        return lower...(upper > lower ? upper : lower + 1)
    }

    private var voltageRange: ClosedRange<Double>? {
        let finiteVoltages = signal.voltageMillivolts.compactMap { value -> Double? in
            guard let value, value.isFinite else { return nil }
            return value
        }
        guard let lower = finiteVoltages.min(), let upper = finiteVoltages.max() else { return nil }
        let span = upper - lower
        let padding = span > 0 ? span * 0.12 : 0.5
        return (lower - padding)...(upper + padding)
    }

    private func chartWidth(minimumWidth: CGFloat, duration: Double) -> CGFloat {
        min(max(minimumWidth, CGFloat(duration * 42 * zoom)), 100_000)
    }

    private func drawGrid(
        context: inout GraphicsContext,
        size: CGSize,
        timeRange: ClosedRange<Double>,
        voltageRange: ClosedRange<Double>
    ) {
        var grid = Path()
        let duration = timeRange.upperBound - timeRange.lowerBound
        let gridInterval = max(1, ceil(duration / 60))
        var gridTime = ceil(timeRange.lowerBound / gridInterval) * gridInterval
        var lineCount = 0
        while gridTime <= timeRange.upperBound, lineCount < 100 {
            if let position = ECGTimeline.normalizedPosition(
                for: gridTime,
                startTimeSeconds: timeRange.lowerBound,
                endTimeSeconds: timeRange.upperBound
            ) {
                let x = CGFloat(position) * size.width
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            gridTime += gridInterval
            lineCount += 1
        }

        if voltageRange.contains(0) {
            let zeroY = yPosition(for: 0, in: voltageRange, height: size.height)
            grid.move(to: CGPoint(x: 0, y: zeroY))
            grid.addLine(to: CGPoint(x: size.width, y: zeroY))
        }
        context.stroke(grid, with: .color(.secondary.opacity(0.18)), lineWidth: 0.5)
    }

    private func drawSignal(
        context: inout GraphicsContext,
        size: CGSize,
        timeRange: ClosedRange<Double>,
        voltageRange: ClosedRange<Double>
    ) {
        let pointLimit = max(400, Int(size.width * 2))
        let displaySamples = ECGDisplayDownsampler.samples(
            from: signal,
            maximumPointCount: pointLimit
        )
        var path = Path()
        var hasOpenSegment = false
        var previousSourceIndex: Int?

        for sample in displaySamples {
            guard sample.timeSeconds.isFinite,
                  let voltage = sample.voltageMillivolts,
                  voltage.isFinite,
                  let xPosition = ECGTimeline.normalizedPosition(
                      for: sample.timeSeconds,
                      startTimeSeconds: timeRange.lowerBound,
                      endTimeSeconds: timeRange.upperBound
                  ) else {
                hasOpenSegment = false
                previousSourceIndex = sample.sourceIndex
                continue
            }

            let point = CGPoint(
                x: CGFloat(xPosition) * size.width,
                y: yPosition(for: voltage, in: voltageRange, height: size.height)
            )
            if hasOpenSegment,
               let previousSourceIndex,
               sample.sourceIndex > previousSourceIndex {
                path.addLine(to: point)
            } else {
                path.move(to: point)
            }
            hasOpenSegment = true
            previousSourceIndex = sample.sourceIndex
        }

        context.stroke(
            path,
            with: .color(.blue),
            style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawMarkers(
        context: inout GraphicsContext,
        size: CGSize,
        timeRange: ClosedRange<Double>
    ) {
        for marker in markers {
            guard marker.timeSeconds >= timeRange.lowerBound,
                  marker.timeSeconds <= timeRange.upperBound,
                  let position = ECGTimeline.normalizedPosition(
                      for: marker.timeSeconds,
                      startTimeSeconds: timeRange.lowerBound,
                      endTimeSeconds: timeRange.upperBound
                  ) else { continue }
            let x = CGFloat(position) * size.width
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(.orange), lineWidth: 1)
        }
    }

    private func yPosition(
        for voltage: Double,
        in range: ClosedRange<Double>,
        height: CGFloat
    ) -> CGFloat {
        let normalized = (voltage - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(1 - normalized) * height
    }
}
