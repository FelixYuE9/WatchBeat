import ECGCore
import Foundation
import SwiftUI
import WatchBeatModels

/// Settings keys for research-only waveform overlays. Both default to off: the R–R strip above the
/// waveform already carries the timing information needed for everyday reading, and full-height
/// model lines are only useful when checking how the detector behaves.
public enum ECGWaveformDebugSettings {
    public static let showsModelRPeakLinesKey = "debug.waveform.showsModelRPeakLines"
    public static let showsCandidateLinesKey = "debug.waveform.showsCandidateLines"
}

/// Asks the waveform to bring a timestamp into view, including times without a candidate.
public struct ECGWaveformFocusRequest: Equatable {
    public let timeSeconds: Double

    public init(timeSeconds: Double) {
        self.timeSeconds = timeSeconds
    }
}

private struct ECGWaveformScrollTarget: Equatable {
    let id = UUID()
    let timeSeconds: Double
    let animated: Bool
}

/// Emitted by the laid-out anchor so scrolling waits until its new position is registered.
private struct ECGWaveformScrollAnchor: Equatable {
    let target: ECGWaveformScrollTarget
    let x: CGFloat
    let chartWidth: CGFloat
}

private struct ECGWaveformScrollAnchorKey: PreferenceKey {
    static let defaultValue: ECGWaveformScrollAnchor? = nil

    static func reduce(value: inout ECGWaveformScrollAnchor?, nextValue: () -> ECGWaveformScrollAnchor?) {
        value = nextValue() ?? value
    }
}

private struct ECGWaveformViewportKey: PreferenceKey {
    static let defaultValue: ECGWaveformViewport? = nil

    static func reduce(value: inout ECGWaveformViewport?, nextValue: () -> ECGWaveformViewport?) {
        value = nextValue() ?? value
    }
}

/// Maps between signal time/voltage and points inside the scrollable chart.
struct ECGChartGeometry: Equatable {
    static let coordinateSpaceName = "watchbeat.waveform.chart"

    let timeRange: ClosedRange<Double>
    let voltageRange: ClosedRange<Double>
    let width: CGFloat
    let topInset: CGFloat
    let drawableHeight: CGFloat

    var waveformBottom: CGFloat { topInset + drawableHeight }

    func x(for time: Double) -> CGFloat {
        let position = ECGTimeline.normalizedPosition(
            for: time,
            startTimeSeconds: timeRange.lowerBound,
            endTimeSeconds: timeRange.upperBound
        ) ?? 0
        return CGFloat(position) * width
    }

    func time(forX x: CGFloat) -> Double {
        let fraction = min(max(Double(x / max(width, 1)), 0), 1)
        return timeRange.lowerBound + fraction * (timeRange.upperBound - timeRange.lowerBound)
    }

    func y(for voltage: Double) -> CGFloat {
        let normalized = (voltage - voltageRange.lowerBound)
            / (voltageRange.upperBound - voltageRange.lowerBound)
        return topInset + CGFloat(1 - normalized) * drawableHeight
    }

    func voltage(forY y: CGFloat) -> Double {
        let fraction = min(max(1 - Double((y - topInset) / max(drawableHeight, 1)), 0), 1)
        return voltageRange.lowerBound + fraction * (voltageRange.upperBound - voltageRange.lowerBound)
    }
}

/// Keeps the last display envelope so redraws that do not change the chart width (vertical zoom,
/// overlay toggles, candidate focus) skip rescanning the full-resolution signal.
private final class ECGDisplaySampleCache {
    private var key: (sampleCount: Int, pointLimit: Int)?
    private var cached: [ECGDisplaySample] = []

    func samples(for signal: ECGSignal, maximumPointCount: Int) -> [ECGDisplaySample] {
        if let key,
           key.sampleCount == signal.timeSeconds.count,
           key.pointLimit == maximumPointCount {
            return cached
        }
        cached = ECGDisplayDownsampler.samples(from: signal, maximumPointCount: maximumPointCount)
        key = (signal.timeSeconds.count, maximumPointCount)
        return cached
    }
}

/// A horizontally scrollable waveform. Drawing uses a timestamp-preserving display envelope;
/// `signal` itself remains full resolution for analysis and export.
public struct ECGWaveformView: View {
    private let signal: ECGSignal
    private let markers: [ECGWaveformMarker]
    private let candidates: [ECGWaveformMarker]
    private let intervals: [ECGPeakInterval]
    private let candidateIDs: Set<String>
    private let qrsAmplitudes: [ECGQRSAmplitude]
    /// Computed once per init; scanning every sample on each redraw made zooming sluggish.
    private let timeRange: ClosedRange<Double>?
    private let voltageRange: ClosedRange<Double>?
    @Binding private var focusRequest: ECGWaveformFocusRequest?

    @State private var zoom = 1.0
    @State private var verticalZoom = 1.0
    @State private var focusedCandidateIndex: Int?
    @State private var isMeasuring = false
    @State private var caliper = ECGCaliper()
    @State private var displayCache = ECGDisplaySampleCache()
    @State private var overviewCache = ECGDisplaySampleCache()
    @State private var viewport: ECGWaveformViewport?
    @State private var scrollTarget: ECGWaveformScrollTarget?
    @AppStorage("waveform.showsRRIntervals") private var showsRRIntervals = true
    @AppStorage("waveform.showsQRSAmplitude") private var showsQRSAmplitude = true
    @AppStorage(ECGWaveformDebugSettings.showsModelRPeakLinesKey) private var showsModelRPeakLines = false
    @AppStorage(ECGWaveformDebugSettings.showsCandidateLinesKey) private var showsCandidateLines = false
    @Environment(\.appLanguage) private var language

    private let baseDrawableHeight: CGFloat = 180
    private let axisGutterWidth: CGFloat = 40
    private let waveformBottomInset: CGFloat = 30
    private let candidateBandHalfWidthSeconds = 0.16
    private let viewportCoordinateSpace = "watchbeat.waveform.viewport"

    public init(
        signal: ECGSignal,
        markers: [ECGWaveformMarker] = [],
        focusRequest: Binding<ECGWaveformFocusRequest?> = .constant(nil)
    ) {
        self.signal = signal
        self.markers = markers
        let candidates = markers.filter(\.isPrematureCandidate)
        self.candidates = candidates
        self.intervals = ECGPeakIntervalBuilder.intervals(between: markers)
        self.candidateIDs = Set(candidates.map(\.id))
        self.timeRange = Self.makeTimeRange(of: signal)
        self.voltageRange = Self.makeVoltageRange(of: signal)
        self.qrsAmplitudes = Self.makeQRSAmplitudes(signal: signal, markers: markers)
        _focusRequest = focusRequest
    }

    public var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 10) {
                header

                if let timeRange, let voltageRange {
                    zoomControls
                    overlayToggles

                    if !candidates.isEmpty {
                        candidateNavigator
                    }

                    chart(timeRange: timeRange, voltageRange: voltageRange, proxy: proxy)
                    overview(timeRange: timeRange, voltageRange: voltageRange)

                    legend

                    if isMeasuring {
                        ECGCaliperReadout(caliper: caliper, signal: signal)
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
            .onChange(of: focusRequest) { _, request in
                guard let request else { return }
                focusRequest = nil
                focusedCandidateIndex = candidates.firstIndex {
                    abs($0.timeSeconds - request.timeSeconds) < 0.001
                }
                focusTime(request.timeSeconds, animated: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Controls

    private var header: some View {
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
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            VStack(spacing: 6) {
                zoomRow(
                    symbol: "arrow.left.and.right",
                    value: timeZoomBinding,
                    range: 1...8,
                    step: 0.5,
                    accessibilityLabel: language.text("Time zoom", "时间轴缩放")
                )
                zoomRow(
                    symbol: "arrow.up.and.down",
                    value: $verticalZoom,
                    range: 1...4,
                    step: 0.25,
                    accessibilityLabel: language.text("Voltage zoom", "电压轴缩放")
                )
            }
            Button {
                setTimeZoom(1)
                verticalZoom = 1
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .disabled(zoom == 1 && verticalZoom == 1)
            .accessibilityLabel(language.text("Reset zoom", "复位缩放"))
        }
    }

    private var timeZoomBinding: Binding<Double> {
        Binding(get: { zoom }, set: { setTimeZoom($0) })
    }

    private func setTimeZoom(_ value: Double) {
        guard value != zoom else { return }
        // Capture the old window before the changed chart width can publish new geometry.
        let center: Double?
        if let focusedCandidateIndex, candidates.indices.contains(focusedCandidateIndex) {
            center = candidates[focusedCandidateIndex].timeSeconds
        } else {
            center = viewport?.centerTimeSeconds
        }
        zoom = value
        if let center { focusTime(center, animated: false) }
    }

    private func zoomRow(
        symbol: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        accessibilityLabel: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(accessibilityLabel)
            Text(Self.zoomText(value.wrappedValue))
                .font(.caption.monospacedDigit())
                .frame(width: 42, alignment: .trailing)
        }
    }

    /// Icon-only switches; the legend below the chart repeats each icon with its meaning.
    private var overlayToggles: some View {
        HStack(spacing: 16) {
            overlayToggle(
                isOn: $isMeasuring,
                title: language.text("Measure", "测量"),
                symbol: "ruler",
                tint: .purple
            )
            if markers.count > 1 {
                overlayToggle(
                    isOn: $showsRRIntervals,
                    title: language.text("R–R intervals", "R–R 间期"),
                    symbol: "arrow.left.and.right.square",
                    tint: .pink
                )
            }
            if !qrsAmplitudes.isEmpty {
                overlayToggle(
                    isOn: $showsQRSAmplitude,
                    title: language.text("Peak-to-trough voltage", "峰谷电压差"),
                    symbol: "arrow.up.and.down.square",
                    tint: .teal
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func overlayToggle(
        isOn: Binding<Bool>,
        title: String,
        symbol: String,
        tint: Color
    ) -> some View {
        Toggle(isOn: isOn) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 44, height: 30)
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .tint(tint)
        .accessibilityLabel(title)
    }

    private var candidateNavigator: some View {
        HStack(spacing: 10) {
            Image(systemName: "flag.fill")
                .foregroundStyle(Color.watchBeatAttentionText)
            VStack(alignment: .leading, spacing: 2) {
                Text(language.text(
                    "\(candidates.count) premature candidate(s)",
                    "\(candidates.count) 处疑似早搏候选"
                ))
                .font(.subheadline.bold())
                Text(navigatorSubtitle)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                stepCandidate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel(language.text("Previous candidate", "上一个候选"))
            Button {
                stepCandidate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel(language.text("Next candidate", "下一个候选"))
        }
        .buttonStyle(.bordered)
        .padding(10)
        .background(Color.watchBeatAttention.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
    }

    private var navigatorSubtitle: String {
        guard let focusedCandidateIndex, candidates.indices.contains(focusedCandidateIndex) else {
            return language.text(
                "Tap › to jump to each one",
                "点击 › 逐个跳转查看"
            )
        }
        let time = candidates[focusedCandidateIndex].timeSeconds
        return language.text(
            String(format: "%ld of %ld · %.3f s", focusedCandidateIndex + 1, candidates.count, time),
            String(format: "第 %ld/%ld 处 · %.3f 秒", focusedCandidateIndex + 1, candidates.count, time)
        )
    }

    // MARK: - Chart

    private func chart(
        timeRange: ClosedRange<Double>,
        voltageRange: ClosedRange<Double>,
        proxy: ScrollViewProxy
    ) -> some View {
        GeometryReader { container in
            let viewportWidth = max(container.size.width - axisGutterWidth, 1)
            let geometry = ECGChartGeometry(
                timeRange: timeRange,
                voltageRange: voltageRange,
                width: chartWidth(
                    minimumWidth: viewportWidth,
                    duration: timeRange.upperBound - timeRange.lowerBound
                ),
                topInset: waveformTopInset,
                drawableHeight: drawableHeight
            )
            let voltageTicks = ECGVoltageAxis.majorTicks(
                lowerMillivolts: voltageRange.lowerBound,
                upperMillivolts: voltageRange.upperBound,
                chartHeightPoints: Double(drawableHeight)
            )

            HStack(spacing: 0) {
                voltageAxis(geometry: geometry, ticks: voltageTicks)
                ScrollView(.horizontal) {
                    chartContent(geometry: geometry, voltageTicks: voltageTicks, viewportWidth: viewportWidth)
                        .background {
                            GeometryReader { content in
                                Color.clear.preference(
                                    key: ECGWaveformViewportKey.self,
                                    value: ECGWaveformViewport(
                                        timeRange: timeRange,
                                        contentWidthPoints: Double(geometry.width),
                                        viewportWidthPoints: Double(viewportWidth),
                                        offsetPoints: -Double(content.frame(in: .named(viewportCoordinateSpace)).minX)
                                    )
                                )
                            }
                        }
                }
                .scrollIndicators(.visible)
                .coordinateSpace(.named(viewportCoordinateSpace))
                .onPreferenceChange(ECGWaveformViewportKey.self) { viewport = $0 }
                .onPreferenceChange(ECGWaveformScrollAnchorKey.self) { anchor in
                    guard let anchor else { return }
                    Task { @MainActor in
                        // Layout must finish before scrollTo resolves a newly moved anchor.
                        // A newer drag event supersedes any still-pending request.
                        guard anchor.target.id == scrollTarget?.id else { return }
                        if anchor.target.animated {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(anchor.target.id, anchor: .center)
                            }
                        } else {
                            proxy.scrollTo(anchor.target.id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(height: chartHeight)
    }

    private func chartContent(
        geometry: ECGChartGeometry,
        voltageTicks: [Double],
        viewportWidth: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let timeTicks = ECGTimeline.majorTickTimes(
                    startTimeSeconds: geometry.timeRange.lowerBound,
                    endTimeSeconds: geometry.timeRange.upperBound,
                    chartWidthPoints: Double(size.width)
                )
                drawGrid(context: &context, size: size, geometry: geometry, timeTicks: timeTicks, voltageTicks: voltageTicks)
                drawCandidateBands(context: &context, geometry: geometry)
                if showsRRIntervals {
                    drawRRStrip(context: &context, geometry: geometry)
                }
                drawSignal(context: &context, size: size, geometry: geometry)
                if showsQRSAmplitude {
                    drawQRSAmplitudes(context: &context, geometry: geometry)
                }
                drawDebugLines(context: &context, geometry: geometry)
                drawCandidateTimeLabels(context: &context, size: size, geometry: geometry)
                drawTimeAxis(context: &context, size: size, geometry: geometry, timeTicks: timeTicks)
            }

            scrollTargetAnchor(geometry: geometry, viewportWidth: viewportWidth)

            if isMeasuring {
                ECGCaliperOverlay(caliper: caliper, signal: signal, geometry: geometry, height: chartHeight)
            }
        }
        .frame(width: geometry.width, height: chartHeight)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .coordinateSpace(.named(ECGChartGeometry.coordinateSpaceName))
        .onTapGesture { location in
            guard isMeasuring else { return }
            caliper.placeActivePoint(at: location, geometry: geometry, signal: signal)
        }
    }

    /// Kept below the detail chart so a finger navigating here never covers the enlarged trace.
    /// Its voltage scale and display cache are independent of detail zoom.
    private func overview(timeRange: ClosedRange<Double>, voltageRange: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(language.text("Full recording overview", "全段预览"))
                    .font(.subheadline.bold())
                Spacer(minLength: 4)
                if let viewport {
                    Text(visibleRangeText(viewport.visibleTimeRange))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { container in
                let geometry = ECGChartGeometry(
                    timeRange: timeRange,
                    voltageRange: voltageRange,
                    width: max(container.size.width, 1),
                    topInset: 8,
                    drawableHeight: 76
                )
                let initialViewport = ECGWaveformViewport(
                    timeRange: timeRange,
                    contentWidthPoints: Double(chartWidth(
                        minimumWidth: max(container.size.width - axisGutterWidth, 1),
                        duration: timeRange.upperBound - timeRange.lowerBound
                    )),
                    viewportWidthPoints: Double(max(container.size.width - axisGutterWidth, 1)),
                    offsetPoints: 0
                )
                let visibleRange = (viewport ?? initialViewport)?.visibleTimeRange ?? timeRange

                Canvas { context, size in
                    let interiorTicks = ECGTimeline.majorTickTimes(
                        startTimeSeconds: timeRange.lowerBound,
                        endTimeSeconds: timeRange.upperBound,
                        chartWidthPoints: Double(size.width)
                    )
                    .filter { geometry.x(for: $0) > 40 && geometry.x(for: $0) < size.width - 40 }
                    let timeTicks = [timeRange.lowerBound] + interiorTicks + [timeRange.upperBound]
                    drawGrid(
                        context: &context, size: size, geometry: geometry,
                        timeTicks: timeTicks, voltageTicks: [0]
                    )
                    for candidate in candidates {
                        let x = geometry.x(for: candidate.timeSeconds)
                        let band = CGRect(x: x - 2, y: geometry.topInset, width: 4, height: geometry.drawableHeight)
                        context.fill(Path(band), with: .color(Color.watchBeatAttention.opacity(0.5)))
                    }
                    drawSignal(context: &context, size: size, geometry: geometry, cache: overviewCache)

                    let selection = CGRect(
                        x: geometry.x(for: visibleRange.lowerBound),
                        y: 2,
                        width: max(1, geometry.x(for: visibleRange.upperBound) - geometry.x(for: visibleRange.lowerBound)),
                        height: geometry.waveformBottom + 2
                    )
                    context.fill(Path(selection), with: .color(Color.blue.opacity(0.1)))
                    context.stroke(Path(selection), with: .color(.blue), lineWidth: 1.5)
                    drawTimeAxis(context: &context, size: size, geometry: geometry, timeTicks: timeTicks)
                }
                .background(Color.secondary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            focusedCandidateIndex = nil
                            focusTime(geometry.time(forX: value.location.x), animated: false)
                        }
                )
                .accessibilityElement()
                .accessibilityLabel(language.text("Full ECG overview", "完整心电图概览"))
                .accessibilityValue(visibleRangeText(visibleRange))
                .accessibilityHint(language.text("Swipe up or down to move the detail window", "上下轻扫以移动细节窗口"))
                .accessibilityAdjustableAction { direction in
                    let windowDuration = visibleRange.upperBound - visibleRange.lowerBound
                    let center = (visibleRange.lowerBound + visibleRange.upperBound) / 2
                    focusedCandidateIndex = nil
                    switch direction {
                    case .increment: focusTime(center + windowDuration * 0.75, animated: false)
                    case .decrement: focusTime(center - windowDuration * 0.75, animated: false)
                    @unknown default: break
                    }
                }
            }
            .frame(height: 108)

            Text(language.text(
                "Tap or drag anywhere to view details above. The blue window shows the visible section.",
                "点击或拖动任意位置，查看上方细节；蓝色选框表示当前可见范围。"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func visibleRangeText(_ range: ClosedRange<Double>) -> String {
        language.text(
            String(format: "Viewing %.1f–%.1f s", range.lowerBound, range.upperBound),
            String(format: "当前 %.1f–%.1f 秒", range.lowerBound, range.upperBound)
        )
    }

    /// Fixed millivolt labels; they stay put while the waveform scrolls horizontally.
    private func voltageAxis(geometry: ECGChartGeometry, ticks: [Double]) -> some View {
        Canvas { context, size in
            let decimals = Self.tickDecimals(ticks)
            var tickMarks = Path()
            for tick in ticks {
                let y = geometry.y(for: tick)
                tickMarks.move(to: CGPoint(x: size.width - 4, y: y))
                tickMarks.addLine(to: CGPoint(x: size.width, y: y))
                var label = context.resolve(
                    Text(String(format: "%.\(decimals)f", tick))
                        .font(.caption2.monospacedDigit())
                )
                label.shading = .color(.secondary)
                context.draw(label, at: CGPoint(x: size.width - 6, y: y), anchor: .trailing)
            }
            context.stroke(tickMarks, with: .color(.secondary.opacity(0.45)), lineWidth: 0.7)

            var unit = context.resolve(Text("mV").font(.caption2.bold()))
            unit.shading = .color(.secondary)
            context.draw(unit, at: CGPoint(x: size.width - 6, y: size.height - 8), anchor: .trailing)
        }
        .frame(width: axisGutterWidth, height: chartHeight)
        .accessibilityHidden(true)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                language.text(
                    "Scroll horizontally; the axes are in seconds and millivolts (mV).",
                    "左右滑动查看；横轴单位为秒，纵轴单位为毫伏（mV）。"
                ),
                systemImage: "arrow.left.and.right"
            )
            if markers.count > 1 {
                if showsRRIntervals {
                    Label(
                        language.text(
                            "Numbers above the trace are R–R intervals between adjacent R peaks, in ms.",
                            "波形上方数字是相邻 R 峰之间的间期（毫秒）。"
                        ),
                        systemImage: "arrow.left.and.right.square"
                    )
                }
                if !candidates.isEmpty {
                    Label(
                        language.text(
                            "Yellow shading and #numbers mark premature candidates, and the short R–R before each one is highlighted. Use ‹ › to jump between them.",
                            "黄色底色和 # 序号标出疑似早搏候选，其前方偏短的 R–R 间期以黄色突出；可用 ‹ › 逐个跳转。"
                        ),
                        systemImage: "flag"
                    )
                }
                if showsQRSAmplitude, !qrsAmplitudes.isEmpty {
                    Label(
                        language.text(
                            "Teal values are the peak-to-trough voltage within ±80 ms of each R peak (mV).",
                            "青色数值是每个 R 峰前后 80 毫秒内的峰谷电压差（mV）。"
                        ),
                        systemImage: "arrow.up.and.down.square"
                    )
                }
                if showsModelRPeakLines || showsCandidateLines {
                    Label(
                        language.text(
                            "Debug overlay: orange lines are model R peaks; thick yellow lines are candidates.",
                            "调试标注：橙色细线为模型 R 峰，黄色粗线为疑似早搏候选。"
                        ),
                        systemImage: "ladybug"
                    )
                }
            } else {
                Text(language.text(
                    "No model-derived R–R intervals are available for this signal.",
                    "这段信号没有可用的模型 R–R 间期。"
                ))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Drawing

    private func drawGrid(
        context: inout GraphicsContext,
        size: CGSize,
        geometry: ECGChartGeometry,
        timeTicks: [Double],
        voltageTicks: [Double]
    ) {
        var grid = Path()
        for gridTime in timeTicks {
            let x = geometry.x(for: gridTime)
            grid.move(to: CGPoint(x: x, y: geometry.topInset))
            grid.addLine(to: CGPoint(x: x, y: geometry.waveformBottom))
        }
        for tick in voltageTicks where abs(tick) > 1e-9 {
            let y = geometry.y(for: tick)
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid, with: .color(.secondary.opacity(0.16)), lineWidth: 0.5)

        if geometry.voltageRange.contains(0) {
            var zeroLine = Path()
            let zeroY = geometry.y(for: 0)
            zeroLine.move(to: CGPoint(x: 0, y: zeroY))
            zeroLine.addLine(to: CGPoint(x: size.width, y: zeroY))
            context.stroke(zeroLine, with: .color(.secondary.opacity(0.32)), lineWidth: 0.7)
        }
    }

    /// Soft yellow shading behind each candidate beat: visible while scrolling, without covering
    /// the trace the way a full-height line does.
    private func drawCandidateBands(context: inout GraphicsContext, geometry: ECGChartGeometry) {
        for (index, candidate) in candidates.enumerated() {
            let startX = geometry.x(for: candidate.timeSeconds - candidateBandHalfWidthSeconds)
            let endX = geometry.x(for: candidate.timeSeconds + candidateBandHalfWidthSeconds)
            let centerX = geometry.x(for: candidate.timeSeconds)
            let halfWidth = max((endX - startX) / 2, 8)
            let band = CGRect(
                x: centerX - halfWidth,
                y: geometry.topInset,
                width: halfWidth * 2,
                height: geometry.drawableHeight
            )
            let opacity = index == focusedCandidateIndex ? 0.36 : 0.18
            context.fill(
                Path(roundedRect: band, cornerRadius: 6),
                with: .color(Color.watchBeatAttention.opacity(opacity))
            )
        }
    }

    private func drawRRStrip(context: inout GraphicsContext, geometry: ECGChartGeometry) {
        let bracketY: CGFloat = 29
        let labelY: CGFloat = 12
        for interval in intervals {
            let startX = geometry.x(for: interval.startTimeSeconds)
            let endX = geometry.x(for: interval.endTimeSeconds)
            let endsAtCandidate = candidateIDs.contains(interval.endMarkerID)

            var bracket = Path()
            bracket.move(to: CGPoint(x: startX, y: bracketY))
            bracket.addLine(to: CGPoint(x: endX, y: bracketY))
            bracket.move(to: CGPoint(x: startX, y: bracketY - 5))
            bracket.addLine(to: CGPoint(x: startX, y: bracketY + 5))
            bracket.move(to: CGPoint(x: endX, y: bracketY - 5))
            bracket.addLine(to: CGPoint(x: endX, y: bracketY + 5))
            context.stroke(
                bracket,
                with: .color(endsAtCandidate ? Color.watchBeatAttention : Color.secondary.opacity(0.6)),
                lineWidth: endsAtCandidate ? 1.6 : 1
            )

            let milliseconds = Int(interval.durationMilliseconds.rounded())
            var label = context.resolve(
                Text("\(milliseconds) ms").font(.caption2.bold().monospacedDigit())
            )
            let center = CGPoint(x: (startX + endX) / 2, y: labelY)
            if endsAtCandidate {
                // The short interval ending at a candidate is the evidence; give it a yellow pill.
                label.shading = .color(Color.watchBeatAttentionText)
                let textSize = label.measure(in: CGSize(width: 200, height: 40))
                let pill = CGRect(
                    x: center.x - textSize.width / 2 - 5,
                    y: center.y - textSize.height / 2 - 2,
                    width: textSize.width + 10,
                    height: textSize.height + 4
                )
                context.fill(
                    Path(roundedRect: pill, cornerRadius: pill.height / 2),
                    with: .color(Color.watchBeatAttention.opacity(0.32))
                )
            }
            context.draw(label, at: center, anchor: .center)
        }
    }

    private func drawSignal(
        context: inout GraphicsContext,
        size: CGSize,
        geometry: ECGChartGeometry,
        cache: ECGDisplaySampleCache? = nil
    ) {
        let pointLimit = max(400, Int(size.width * 2))
        let displaySamples = (cache ?? displayCache).samples(for: signal, maximumPointCount: pointLimit)
        var path = Path()
        var hasOpenSegment = false
        var previousSourceIndex: Int?

        for sample in displaySamples {
            guard sample.timeSeconds.isFinite,
                  let voltage = sample.voltageMillivolts,
                  voltage.isFinite,
                  ECGTimeline.normalizedPosition(
                      for: sample.timeSeconds,
                      startTimeSeconds: geometry.timeRange.lowerBound,
                      endTimeSeconds: geometry.timeRange.upperBound
                  ) != nil else {
                hasOpenSegment = false
                previousSourceIndex = sample.sourceIndex
                continue
            }

            let point = CGPoint(x: geometry.x(for: sample.timeSeconds), y: geometry.y(for: voltage))
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

    /// A thin bracket from trough to peak beside each R peak, labelled with the difference.
    private func drawQRSAmplitudes(context: inout GraphicsContext, geometry: ECGChartGeometry) {
        var brackets = Path()
        for amplitude in qrsAmplitudes {
            let peakTime = signal.timeSeconds[amplitude.maximumSampleIndex]
            let x = geometry.x(for: peakTime) - 6
            let topY = geometry.y(for: amplitude.maximumMillivolts)
            let bottomY = geometry.y(for: amplitude.minimumMillivolts)
            brackets.move(to: CGPoint(x: x, y: topY))
            brackets.addLine(to: CGPoint(x: x, y: bottomY))
            brackets.move(to: CGPoint(x: x - 2.5, y: topY))
            brackets.addLine(to: CGPoint(x: x + 2.5, y: topY))
            brackets.move(to: CGPoint(x: x - 2.5, y: bottomY))
            brackets.addLine(to: CGPoint(x: x + 2.5, y: bottomY))

            var label = context.resolve(
                Text(String(format: "%.2f", amplitude.peakToTroughMillivolts))
                    .font(.caption2.bold().monospacedDigit())
            )
            label.shading = .color(.teal)
            context.draw(label, at: CGPoint(x: x + 6, y: topY - 3), anchor: .bottom)
        }
        context.stroke(brackets, with: .color(.teal.opacity(0.8)), lineWidth: 1)
    }

    /// Research-only full-height lines, enabled from Settings › Research debugging.
    private func drawDebugLines(context: inout GraphicsContext, geometry: ECGChartGeometry) {
        guard showsModelRPeakLines || showsCandidateLines else { return }
        for marker in markers {
            let isCandidate = marker.isPrematureCandidate
            guard isCandidate ? showsCandidateLines : showsModelRPeakLines,
                  marker.timeSeconds >= geometry.timeRange.lowerBound,
                  marker.timeSeconds <= geometry.timeRange.upperBound else { continue }
            let x = geometry.x(for: marker.timeSeconds)
            var path = Path()
            path.move(to: CGPoint(x: x, y: geometry.topInset))
            path.addLine(to: CGPoint(x: x, y: geometry.waveformBottom))
            context.stroke(
                path,
                with: .color(isCandidate ? Color.watchBeatAttention : Color.orange),
                lineWidth: isCandidate ? 2 : 1
            )
        }
    }

    private func drawCandidateTimeLabels(
        context: inout GraphicsContext,
        size: CGSize,
        geometry: ECGChartGeometry
    ) {
        for (index, candidate) in candidates.enumerated() {
            let x = geometry.x(for: candidate.timeSeconds)
            var label = context.resolve(
                Text(candidateTimeLabel(candidate.timeSeconds, number: index + 1))
                    .font(.caption2.bold().monospacedDigit())
            )
            label.shading = .color(Color.watchBeatAttentionText)
            context.draw(
                label,
                at: CGPoint(x: x, y: geometry.waveformBottom - 4),
                anchor: timeLabelAnchor(forX: x, width: size.width, vertical: .bottom)
            )
        }
    }

    private func drawTimeAxis(
        context: inout GraphicsContext,
        size: CGSize,
        geometry: ECGChartGeometry,
        timeTicks: [Double]
    ) {
        let axisY = geometry.waveformBottom
        var axis = Path()
        axis.move(to: CGPoint(x: 0, y: axisY))
        axis.addLine(to: CGPoint(x: size.width, y: axisY))

        for tick in timeTicks {
            let x = geometry.x(for: tick)
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

    // MARK: - Timeline navigation

    /// One exact-time anchor works for overview navigation as well as candidate jumps. Emitting
    /// its preference after layout avoids scrolling to its previous position during a drag/zoom.
    @ViewBuilder
    private func scrollTargetAnchor(geometry: ECGChartGeometry, viewportWidth: CGFloat) -> some View {
        if let scrollTarget,
           let layout = ECGWaveformViewport(
               timeRange: geometry.timeRange,
               contentWidthPoints: Double(geometry.width),
               viewportWidthPoints: Double(viewportWidth),
               offsetPoints: 0
           ) {
            let x = CGFloat(layout.offsetPoints(centering: scrollTarget.timeSeconds)) + viewportWidth / 2
            HStack(spacing: 0) {
                Color.clear.frame(width: max(0, x - 0.5), height: 1)
                Color.clear.frame(width: 1, height: 1)
                    .id(scrollTarget.id)
                    .background {
                        GeometryReader { anchor in
                            Color.clear.preference(
                                key: ECGWaveformScrollAnchorKey.self,
                                value: anchor.size.width > 0 ? ECGWaveformScrollAnchor(
                                    target: scrollTarget,
                                    x: x,
                                    chartWidth: geometry.width
                                ) : nil
                            )
                        }
                    }
                Spacer(minLength: 0)
            }
            .frame(width: geometry.width, height: 1, alignment: .leading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func stepCandidate(by delta: Int) {
        guard !candidates.isEmpty else { return }
        let next: Int
        if let focusedCandidateIndex {
            next = (focusedCandidateIndex + delta + candidates.count) % candidates.count
        } else {
            next = delta > 0 ? 0 : candidates.count - 1
        }
        focusedCandidateIndex = next
        focusTime(candidates[next].timeSeconds, animated: true)
    }

    private func focusTime(_ time: Double, animated: Bool) {
        guard time.isFinite else { return }
        scrollTarget = ECGWaveformScrollTarget(timeSeconds: time, animated: animated)
    }

    // MARK: - Layout

    private var waveformTopInset: CGFloat {
        markers.count > 1 && showsRRIntervals ? 44 : 14
    }

    private var drawableHeight: CGFloat {
        baseDrawableHeight * CGFloat(verticalZoom)
    }

    private var chartHeight: CGFloat {
        waveformTopInset + drawableHeight + waveformBottomInset
    }

    private func chartWidth(minimumWidth: CGFloat, duration: Double) -> CGFloat {
        let pointsPerSecond = markers.count > 1 ? 84.0 : 42.0
        return min(max(max(minimumWidth, 1), CGFloat(duration * pointsPerSecond * zoom)), 100_000)
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

    private func candidateTimeLabel(_ time: Double, number: Int) -> String {
        language.text(
            String(format: "#%ld %.3f s", number, time),
            String(format: "#%ld %.3f 秒", number, time)
        )
    }

    // MARK: - Precomputation

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

    /// Uses the same ECGCore measurement as the report, so on-screen brackets match the
    /// exported `qrsPeakToTroughMillivolts` values.
    private static func makeQRSAmplitudes(
        signal: ECGSignal,
        markers: [ECGWaveformMarker]
    ) -> [ECGQRSAmplitude] {
        let times = signal.timeSeconds
        guard times.count == signal.voltageMillivolts.count,
              times.count >= 2,
              let first = times.first,
              let last = times.last,
              first.isFinite,
              last.isFinite,
              last > first else {
            return []
        }
        let samplingFrequencyHz = Double(times.count - 1) / (last - first)
        return markers.compactMap { marker in
            guard let sampleIndex = marker.sampleIndex else { return nil }
            return ECGQRSAmplitude.measure(
                voltageMillivolts: signal.voltageMillivolts,
                around: sampleIndex,
                samplingFrequencyHz: samplingFrequencyHz
            )
        }
    }

    private static func zoomText(_ value: Double) -> String {
        if value == value.rounded() { return String(format: "%.0f×", value) }
        if value * 10 == (value * 10).rounded() { return String(format: "%.1f×", value) }
        return String(format: "%.2f×", value)
    }

    private static func tickDecimals(_ ticks: [Double]) -> Int {
        guard ticks.count >= 2 else { return 1 }
        let step = abs(ticks[1] - ticks[0])
        if step >= 0.999 { return 0 }
        if step >= 0.099 { return 1 }
        return 2
    }
}
