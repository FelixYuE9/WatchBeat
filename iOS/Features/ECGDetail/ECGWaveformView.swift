import ECGCore
import SwiftUI
import WatchBeatModels

/// A horizontally scrollable waveform. Drawing uses a timestamp-preserving display envelope;
/// `signal` itself remains full resolution for analysis and export.
public struct ECGWaveformView: View {
    private let signal: ECGSignal
    private let markers: [ECGWaveformMarker]
    /// Computed once; scanning every sample on each redraw made zooming sluggish.
    private let timeRange: ClosedRange<Double>?
    private let voltageRange: ClosedRange<Double>?
    @State private var zoom = 1.0
    @Environment(\.appLanguage) private var language

    public init(signal: ECGSignal, markers: [ECGWaveformMarker] = []) {
        self.signal = signal
        self.markers = markers
        self.timeRange = Self.makeTimeRange(of: signal)
        self.voltageRange = Self.makeVoltageRange(of: signal)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language.text("Waveform", "波形"))
                    .font(.headline)
                Spacer()
                Text(language.text(
                    "\(signal.timeSeconds.count) full-resolution samples",
                    "\(signal.timeSeconds.count) 个全分辨率采样点"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let timeRange, let voltageRange {
                HStack(spacing: 10) {
                    Image(systemName: "minus.magnifyingglass")
                    Slider(value: $zoom, in: 1...8, step: 0.5)
                        .accessibilityLabel(language.text("Waveform zoom", "波形缩放"))
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
                    Text(language.text("Scroll horizontally", "左右滑动查看"))
                    Spacer()
                    Text(String(format: "%.2f s", timeRange.upperBound))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if markers.count > 1 {
                    Label(
                        language.text(
                            "Orange lines are model R peaks; red lines are premature candidates.",
                            "橙线是模型 R 峰；红线是疑似早搏候选。"
                        ),
                        systemImage: "ruler"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(language.text(
                        "No model-derived R–R intervals are available for this signal.",
                        "这段信号没有可用的模型 R–R 间期。"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView(
                    language.text("Waveform unavailable", "波形不可用"),
                    systemImage: "waveform.path.ecg",
                    description: Text(language.text(
                        "No finite timestamp and voltage pair can be drawn.",
                        "没有可绘制的有限时间戳与电压数据。"
                    ))
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private static func makeTimeRange(of signal: ECGSignal) -> ClosedRange<Double>? {
        let finiteTimes = signal.timeSeconds.filter { $0.isFinite }
        guard let lower = finiteTimes.min(), let upper = finiteTimes.max() else { return nil }
        return lower...(upper > lower ? upper : lower + 1)
    }

    private static func makeVoltageRange(of signal: ECGSignal) -> ClosedRange<Double>? {
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
        let pointsPerSecond = markers.count > 1 ? 84.0 : 42.0
        return min(max(minimumWidth, CGFloat(duration * pointsPerSecond * zoom)), 100_000)
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
                grid.move(to: CGPoint(x: x, y: waveformTopInset))
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
        let intervals = ECGPeakIntervalBuilder.intervals(between: markers)
        for interval in intervals {
            guard let startPosition = ECGTimeline.normalizedPosition(
                for: interval.startTimeSeconds,
                startTimeSeconds: timeRange.lowerBound,
                endTimeSeconds: timeRange.upperBound
            ), let endPosition = ECGTimeline.normalizedPosition(
                for: interval.endTimeSeconds,
                startTimeSeconds: timeRange.lowerBound,
                endTimeSeconds: timeRange.upperBound
            ) else { continue }

            let startX = CGFloat(startPosition) * size.width
            let endX = CGFloat(endPosition) * size.width
            let bracketY: CGFloat = 29
            var bracket = Path()
            bracket.move(to: CGPoint(x: startX, y: bracketY))
            bracket.addLine(to: CGPoint(x: endX, y: bracketY))
            bracket.move(to: CGPoint(x: startX, y: bracketY - 5))
            bracket.addLine(to: CGPoint(x: startX, y: bracketY + 5))
            bracket.move(to: CGPoint(x: endX, y: bracketY - 5))
            bracket.addLine(to: CGPoint(x: endX, y: bracketY + 5))
            context.stroke(bracket, with: .color(.orange), lineWidth: 1)

            let milliseconds = Int(interval.durationMilliseconds.rounded())
            context.draw(
                Text("\(milliseconds) ms").font(.caption2.bold()),
                at: CGPoint(x: (startX + endX) / 2, y: 12),
                anchor: .center
            )
        }

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
            path.move(to: CGPoint(x: x, y: waveformTopInset))
            path.addLine(to: CGPoint(x: x, y: size.height))
            let markerColor: Color = marker.label == "Early" ? .red : .orange
            context.stroke(path, with: .color(markerColor), lineWidth: marker.label == "Early" ? 2 : 1)
        }
    }

    private func yPosition(
        for voltage: Double,
        in range: ClosedRange<Double>,
        height: CGFloat
    ) -> CGFloat {
        let normalized = (voltage - range.lowerBound) / (range.upperBound - range.lowerBound)
        let drawableHeight = max(1, height - waveformTopInset)
        return waveformTopInset + CGFloat(1 - normalized) * drawableHeight
    }

    private var waveformTopInset: CGFloat {
        markers.count > 1 ? 44 : 0
    }
}
