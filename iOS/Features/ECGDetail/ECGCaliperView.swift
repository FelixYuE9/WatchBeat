import ECGCore
import Observation
import SwiftUI
import WatchBeatModels

enum ECGCaliperHandle: String, CaseIterable, Identifiable {
    case a = "A"
    case b = "B"

    var id: String { rawValue }

    var other: ECGCaliperHandle {
        self == .a ? .b : .a
    }
}

struct ECGCaliperPoint: Equatable {
    var timeSeconds: Double
    var voltageMillivolts: Double
}

/// Two-point measuring tool for the waveform. Points live in signal units (s, mV), so they stay
/// on the same sample when the chart is zoomed. Only the overlay and readout observe it; the
/// heavy waveform canvas is not redrawn while a point is dragged. UI-confined: only touched from
/// view bodies and gesture handlers.
@Observable
final class ECGCaliper {
    /// Half-width of the window searched by the "peak" and "trough" buttons.
    static let extremumSearchRadiusSeconds = 0.04

    var pointA: ECGCaliperPoint?
    var pointB: ECGCaliperPoint?
    var activeHandle: ECGCaliperHandle = .a
    /// When on, a point takes the recorded voltage at its time instead of the finger height.
    private(set) var snapsToWaveform = true

    func point(_ handle: ECGCaliperHandle) -> ECGCaliperPoint? {
        handle == .a ? pointA : pointB
    }

    var reading: ECGCaliperReading? {
        guard let pointA, let pointB else { return nil }
        return ECGCaliperReading(
            timeASeconds: pointA.timeSeconds,
            voltageAMillivolts: pointA.voltageMillivolts,
            timeBSeconds: pointB.timeSeconds,
            voltageBMillivolts: pointB.voltageMillivolts
        )
    }

    /// A tap moves the active point. While the other point is still unplaced it becomes active, so
    /// two taps place A and then B.
    func placeActivePoint(at location: CGPoint, geometry: ECGChartGeometry, signal: ECGSignal) {
        let handle = activeHandle
        move(handle, to: location, geometry: geometry, signal: signal)
        if point(handle.other) == nil {
            activeHandle = handle.other
        }
    }

    func move(
        _ handle: ECGCaliperHandle,
        to location: CGPoint,
        geometry: ECGChartGeometry,
        signal: ECGSignal
    ) {
        let time = geometry.time(forX: location.x)
        if snapsToWaveform, let snapped = snappedPoint(nearTime: time, signal: signal) {
            set(handle, snapped)
        } else {
            set(handle, ECGCaliperPoint(timeSeconds: time, voltageMillivolts: geometry.voltage(forY: location.y)))
        }
    }

    /// Moves the active point by whole samples, for precise placement with a fingertip.
    func nudgeActivePoint(bySamples steps: Int, signal: ECGSignal) {
        guard let current = point(activeHandle),
              let index = ECGSignalLookup.nearestSampleIndex(
                  to: current.timeSeconds,
                  in: signal.timeSeconds
              ) else { return }
        let target = min(max(index + steps, 0), signal.timeSeconds.count - 1)
        let time = signal.timeSeconds[target]
        if snapsToWaveform, let voltage = finiteVoltage(at: target, signal: signal) {
            set(activeHandle, ECGCaliperPoint(timeSeconds: time, voltageMillivolts: voltage))
        } else {
            set(activeHandle, ECGCaliperPoint(timeSeconds: time, voltageMillivolts: current.voltageMillivolts))
        }
    }

    /// Moves the active point onto the highest or lowest recorded sample within ±40 ms.
    func snapActivePoint(to kind: ECGExtremumKind, signal: ECGSignal) {
        guard let current = point(activeHandle),
              let index = ECGSignalLookup.nearestSampleIndex(
                  to: current.timeSeconds,
                  in: signal.timeSeconds
              ),
              let extremum = ECGSignalLookup.localExtremumIndex(
                  in: signal,
                  around: index,
                  radiusSeconds: Self.extremumSearchRadiusSeconds,
                  kind: kind
              ),
              let voltage = finiteVoltage(at: extremum, signal: signal) else { return }
        set(
            activeHandle,
            ECGCaliperPoint(timeSeconds: signal.timeSeconds[extremum], voltageMillivolts: voltage)
        )
    }

    func setSnapsToWaveform(_ snaps: Bool, signal: ECGSignal) {
        snapsToWaveform = snaps
        guard snaps else { return }
        for handle in ECGCaliperHandle.allCases {
            if let current = point(handle),
               let snapped = snappedPoint(nearTime: current.timeSeconds, signal: signal) {
                set(handle, snapped)
            }
        }
    }

    func reset() {
        pointA = nil
        pointB = nil
        activeHandle = .a
    }

    private func set(_ handle: ECGCaliperHandle, _ point: ECGCaliperPoint) {
        switch handle {
        case .a: pointA = point
        case .b: pointB = point
        }
    }

    private func snappedPoint(nearTime time: Double, signal: ECGSignal) -> ECGCaliperPoint? {
        guard let index = ECGSignalLookup.nearestSampleIndex(to: time, in: signal.timeSeconds),
              let voltage = finiteVoltage(at: index, signal: signal) else { return nil }
        return ECGCaliperPoint(timeSeconds: signal.timeSeconds[index], voltageMillivolts: voltage)
    }

    private func finiteVoltage(at index: Int, signal: ECGSignal) -> Double? {
        guard signal.voltageMillivolts.indices.contains(index),
              let voltage = signal.voltageMillivolts[index],
              voltage.isFinite else { return nil }
        return voltage
    }
}

/// Crosshairs, the Δt/ΔV elbow and draggable handles, drawn above the waveform.
struct ECGCaliperOverlay: View {
    let caliper: ECGCaliper
    let signal: ECGSignal
    let geometry: ECGChartGeometry
    let height: CGFloat
    @Environment(\.appLanguage) private var language

    private var tint: Color { .purple }

    var body: some View {
        // Read observed values here, not inside the Canvas renderer, so changes redraw the overlay.
        let pointA = caliper.pointA
        let pointB = caliper.pointB
        let reading = caliper.reading
        let activeHandle = caliper.activeHandle

        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                for (handle, point) in [(ECGCaliperHandle.a, pointA), (ECGCaliperHandle.b, pointB)] {
                    guard let point else { continue }
                    drawCrosshair(context: &context, size: size, handle: handle, point: point)
                }
                if let pointA, let pointB, let reading {
                    drawElbow(context: &context, from: pointA, to: pointB, reading: reading)
                }
            }
            .allowsHitTesting(false)

            ForEach(ECGCaliperHandle.allCases) { handle in
                if let point = handle == .a ? pointA : pointB {
                    handleView(handle, point: point, isActive: handle == activeHandle)
                }
            }
        }
        .frame(width: geometry.width, height: height)
    }

    private func handleView(_ handle: ECGCaliperHandle, point: ECGCaliperPoint, isActive: Bool) -> some View {
        ZStack {
            Circle()
                .fill(tint.opacity(isActive ? 0.22 : 0.12))
                .frame(width: 34, height: 34)
            Circle()
                .fill(tint)
                .frame(width: isActive ? 14 : 11, height: isActive ? 14 : 11)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .highPriorityGesture(
            DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named(ECGChartGeometry.coordinateSpaceName)
            )
            .onChanged { value in
                caliper.activeHandle = handle
                caliper.move(handle, to: value.location, geometry: geometry, signal: signal)
            }
        )
        .position(x: geometry.x(for: point.timeSeconds), y: geometry.y(for: point.voltageMillivolts))
        .accessibilityElement()
        .accessibilityLabel(language.text("Measurement point \(handle.rawValue)", "测量点 \(handle.rawValue)"))
    }

    private func drawCrosshair(
        context: inout GraphicsContext,
        size: CGSize,
        handle: ECGCaliperHandle,
        point: ECGCaliperPoint
    ) {
        let x = geometry.x(for: point.timeSeconds)
        let y = geometry.y(for: point.voltageMillivolts)
        var lines = Path()
        lines.move(to: CGPoint(x: x, y: geometry.topInset))
        lines.addLine(to: CGPoint(x: x, y: geometry.waveformBottom))
        lines.move(to: CGPoint(x: 0, y: y))
        lines.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(
            lines,
            with: .color(tint.opacity(0.55)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
        )

        var label = context.resolve(Text(handle.rawValue).font(.caption.bold()))
        label.shading = .color(tint)
        context.draw(label, at: CGPoint(x: x + 9, y: y - 9), anchor: .bottomLeading)
    }

    /// Horizontal leg = Δt, vertical leg = ΔV, so both differences read directly off the chart.
    private func drawElbow(
        context: inout GraphicsContext,
        from pointA: ECGCaliperPoint,
        to pointB: ECGCaliperPoint,
        reading: ECGCaliperReading
    ) {
        let start = CGPoint(x: geometry.x(for: pointA.timeSeconds), y: geometry.y(for: pointA.voltageMillivolts))
        let end = CGPoint(x: geometry.x(for: pointB.timeSeconds), y: geometry.y(for: pointB.voltageMillivolts))
        let corner = CGPoint(x: end.x, y: start.y)
        var elbow = Path()
        elbow.move(to: start)
        elbow.addLine(to: corner)
        elbow.addLine(to: end)
        context.stroke(elbow, with: .color(tint), lineWidth: 1.5)

        drawTag(
            context: &context,
            text: String(format: "Δt %+.0f ms", reading.deltaTimeMilliseconds),
            at: CGPoint(x: (start.x + corner.x) / 2, y: start.y - 12)
        )
        drawTag(
            context: &context,
            text: String(format: "ΔV %+.3f mV", reading.deltaVoltageMillivolts),
            at: CGPoint(x: corner.x + 8, y: (corner.y + end.y) / 2),
            anchor: .leading
        )
    }

    private func drawTag(
        context: inout GraphicsContext,
        text: String,
        at point: CGPoint,
        anchor: UnitPoint = .center
    ) {
        var label = context.resolve(Text(text).font(.caption2.bold().monospacedDigit()))
        label.shading = .color(.white)
        let size = label.measure(in: CGSize(width: 240, height: 40))
        let origin = CGPoint(
            x: point.x - size.width * anchor.x - 5,
            y: point.y - size.height * anchor.y - 2
        )
        let tag = CGRect(origin: origin, size: CGSize(width: size.width + 10, height: size.height + 4))
        context.fill(Path(roundedRect: tag, cornerRadius: tag.height / 2), with: .color(tint.opacity(0.9)))
        context.draw(label, at: CGPoint(x: tag.midX, y: tag.midY), anchor: .center)
    }
}

/// Values and fine-adjustment buttons for the caliper, sized for fingertips.
struct ECGCaliperReadout: View {
    @Bindable var caliper: ECGCaliper
    let signal: ECGSignal
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(language.text("Measurement", "测量"), systemImage: "ruler")
                    .font(.subheadline.bold())
                    .foregroundStyle(.purple)
                Spacer()
                Toggle(
                    language.text("Snap to trace", "贴合波形"),
                    isOn: Binding(
                        get: { caliper.snapsToWaveform },
                        set: { caliper.setSnapsToWaveform($0, signal: signal) }
                    )
                )
                .toggleStyle(.switch)
                .fixedSize()
                .font(.caption)
            }

            Picker(language.text("Active point", "当前测量点"), selection: $caliper.activeHandle) {
                ForEach(ECGCaliperHandle.allCases) { handle in
                    Text(language.text("Point \(handle.rawValue)", "点 \(handle.rawValue)"))
                        .tag(handle)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                pointRow(.a, caliper.pointA)
                pointRow(.b, caliper.pointB)
            }

            if let reading = caliper.reading {
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    deltaValue(
                        title: language.text("Δt (B − A)", "时间差 Δt（B − A）"),
                        value: String(format: "%+.0f ms", reading.deltaTimeMilliseconds)
                    )
                    Spacer(minLength: 12)
                    deltaValue(
                        title: language.text("ΔV (B − A)", "电压差 ΔV（B − A）"),
                        value: String(format: "%+.3f mV", reading.deltaVoltageMillivolts)
                    )
                }
                if let rate = reading.equivalentRateBPM {
                    Text(language.text(
                        String(format: "If Δt spans one beat-to-beat cycle: ≈ %.0f BPM", rate),
                        String(format: "若 Δt 为一个心动周期，约合 %.0f 次/分", rate)
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                adjustButton(symbol: "chevron.left", label: language.text("Earlier", "前移")) {
                    caliper.nudgeActivePoint(bySamples: -1, signal: signal)
                }
                adjustButton(symbol: "chevron.right", label: language.text("Later", "后移")) {
                    caliper.nudgeActivePoint(bySamples: 1, signal: signal)
                }
                adjustButton(symbol: "arrow.up.to.line", label: language.text("Peak", "吸附峰")) {
                    caliper.snapActivePoint(to: .maximum, signal: signal)
                }
                adjustButton(symbol: "arrow.down.to.line", label: language.text("Trough", "吸附谷")) {
                    caliper.snapActivePoint(to: .minimum, signal: signal)
                }
                adjustButton(symbol: "xmark", label: language.text("Clear", "清除")) {
                    caliper.reset()
                }
            }
            .disabled(caliper.pointA == nil && caliper.pointB == nil)

            Text(language.text(
                "Tap the trace to place A, then B. Drag a dot, or use the buttons to move the selected point one sample at a time or onto the nearest peak/trough (±40 ms).",
                "依次点击波形放置 A、B；拖动圆点，或用下方按钮把当前点逐个采样点移动、吸附到 ±40 毫秒内的波峰/波谷。"
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func pointRow(_ handle: ECGCaliperHandle, _ point: ECGCaliperPoint?) -> some View {
        HStack {
            Text(handle.rawValue)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.purple.opacity(handle == caliper.activeHandle ? 1 : 0.5), in: Circle())
            if let point {
                Text(language.text(
                    String(format: "%.3f s", point.timeSeconds),
                    String(format: "%.3f 秒", point.timeSeconds)
                ))
                Spacer()
                Text(String(format: "%.3f mV", point.voltageMillivolts))
            } else {
                Text(language.text("Tap the trace to place", "点击波形放置"))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .font(.subheadline.monospacedDigit())
    }

    private func deltaValue(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
        }
    }

    private func adjustButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.body.bold())
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.bordered)
        .tint(.purple)
    }
}
