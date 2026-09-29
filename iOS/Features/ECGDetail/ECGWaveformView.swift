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
    private let chartHeight: CGFloat = 252
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
                            let timeTicks = ECGTimeline.majorTickTimes(
                                startTimeSeconds: timeRange.lowerBound,
                                endTimeSeconds: timeRange.upperBound,
                                chartWidthPoints: Double(size.width)
                            )
                            drawGrid(
                                context: &context,
                                size: size,
                                timeRange: timeRange,
                                voltageRange: voltageRange,
                                timeTicks: timeTicks
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
                            drawTimeAxis(
                                context: &context,
                                size: size,
                                timeRange: timeRange,
                                timeTicks: timeTicks
                            )
                        }
                        .frame(
                            width: chartWidth(
                                minimumWidth: geometry.size.width,
                                duration: timeRange.upperBound - timeRange.lowerBound
                            ),
                            height: chartHeight
                        )
                        .background(Color.secondary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .scrollIndicators(.visible)
                }
                .frame(height: chartHeight)

                Label(
                    language.text(
                        "Scroll horizontally; the seconds axis below moves with the waveform.",
                        "左右滑动查看；下方秒数刻度会随波形一起移动。"
                    ),
                    systemImage: "arrow.left.and.right"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                if markers.count > 1 {
                    Label(
                        language.text(
                            "Orange lines are model R peaks; red lines and exact time labels are premature candidates.",
                            "橙线是模型 R 峰；红线及其精确秒数是疑似早搏候选。"
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
        voltageRange: ClosedRange<Double>,
        timeTicks: [Double]
    ) {
        var grid = Path()
        for gridTime in timeTicks {
            if let position = ECGTimeline.normalizedPosition(
                for: gridTime,
                startTimeSeconds: timeRange.lowerBound,
                endTimeSeconds: timeRange.upperBound
            ) {
                let x = CGFloat(position) * size.width
                grid.move(to: CGPoint(x: x, y: waveformTopInset))
                grid.addLine(to: CGPoint(x: x, y: waveformBottom(in: size)))
            }
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
            let isPremature = marker.label == "Early"
            var path = Path()
            path.move(to: CGPoint(x: x, y: waveformTopInset))
            path.addLine(to: CGPoint(x: x, y: waveformBottom(in: size)))
            let markerColor: Color = isPremature ? .red : .orange
            context.stroke(path, with: .color(markerColor), lineWidth: isPremature ? 2 : 1)

            if isPremature {
                var candidateLabel = context.resolve(
                    Text(candidateTimeLabel(marker.timeSeconds))
                        .font(.caption2.bold().monospacedDigit())
                )
                candidateLabel.shading = .color(Color.red)
                context.draw(
                    candidateLabel,
                    at: CGPoint(x: x, y: waveformBottom(in: size) - 5),
                    anchor: timeLabelAnchor(forX: x, width: size.width, vertical: .bottom)
                )
            }
        }
    }

    private func drawTimeAxis(
        context: inout GraphicsContext,
        size: CGSize,
        timeRange: ClosedRange<Double>,
        timeTicks: [Double]
    ) {
        let axisY = waveformBottom(in: size)
        var axis = Path()
        axis.move(to: CGPoint(x: 0, y: axisY))
        axis.addLine(to: CGPoint(x: size.width, y: axisY))

        for tick in timeTicks {
            guard let position = ECGTimeline.normalizedPosition(
                for: tick,
                startTimeSeconds: timeRange.lowerBound,
                endTimeSeconds: timeRange.upperBound
            ) else { continue }
            let x = CGFloat(position) * size.width
            axis.move(to: CGPoint(x: x, y: axisY))
            axis.addLine(to: CGPoint(x: x, y: axisY + 4))
            var tickLabel = context.resolve(
                Text(timeAxisLabel(tick))
                    .font(.caption2.monospacedDigit())
            )
            tickLabel.shading = .color(Color.secondary)
            context.draw(
                tickLabel,
                at: CGPoint(x: x, y: size.height - 8),
                anchor: timeLabelAnchor(forX: x, width: size.width, vertical: .bottom)
            )
        }
        context.stroke(axis, with: .color(.secondary.opacity(0.45)), lineWidth: 0.7)
    }

    private func yPosition(
        for voltage: Double,
        in range: ClosedRange<Double>,
        height: CGFloat
    ) -> CGFloat {
        let normalized = (voltage - range.lowerBound) / (range.upperBound - range.lowerBound)
        let drawableHeight = max(1, height - waveformTopInset - waveformBottomInset)
        return waveformTopInset + CGFloat(1 - normalized) * drawableHeight
    }

    private func waveformBottom(in size: CGSize) -> CGFloat {
        size.height - waveformBottomInset
    }

    private func timeLabelAnchor(forX x: CGFloat, width: CGFloat, vertical: UnitPoint) -> UnitPoint {
        let horizontal: CGFloat
        if x < 28 {
            horizontal = 0
        } else if x > width - 28 {
            horizontal = 1
        } else {
            horizontal = 0.5
        }
        return UnitPoint(x: horizontal, y: vertical.y)
    }

    private func timeAxisLabel(_ time: Double) -> String {
        let whole = time.rounded()
        let tenths = (time * 10).rounded() / 10
        let value: String
        if abs(time - whole) < 0.000_5 {
            value = String(format: "%.0f", time)
        } else if abs(time - tenths) < 0.000_05 {
            value = String(format: "%.1f", time)
        } else {
            value = String(format: "%.2f", time)
        }
        return language.text("\(value) s", "\(value) 秒")
    }

    private func candidateTimeLabel(_ time: Double) -> String {
        language.text(
            String(format: "%.3f s", time),
            String(format: "%.3f 秒", time)
        )
    }

    private var waveformTopInset: CGFloat {
        markers.count > 1 ? 44 : 0
    }

    private var waveformBottomInset: CGFloat { 30 }
}
