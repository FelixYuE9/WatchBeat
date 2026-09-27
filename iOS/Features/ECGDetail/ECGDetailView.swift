import SwiftUI
import WatchBeatModels

public struct ECGDetailView: View {
    @State private var viewModel: ECGDetailViewModel
    @State private var pendingExportKind: ECGExportKind?
    @State private var sharedExport: ECGTemporaryExportFile?
    @State private var showsExportError = false
    @Environment(\.appLanguage) private var language

    public init(viewModel: ECGDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ZStack {
            WatchBeatBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metadataSection
                    stateSection
                    disclaimerSection
                }
                .padding()
            }
        }
        .navigationTitle(language.text("ECG Record", "心电图详情"))
        .task { await viewModel.load() }
        .confirmationDialog(
            exportConfirmationTitle,
            isPresented: showsExportConfirmation,
            presenting: pendingExportKind
        ) { kind in
            Button(language.text("Continue to Share", "继续分享")) {
                prepareExport(kind: kind)
            }
            Button(language.text("Cancel", "取消"), role: .cancel) {}
        } message: { _ in
            Text(exportConfirmationMessage)
        }
        .sheet(item: $sharedExport) { file in
            #if canImport(UIKit)
            ECGShareSheet(file: file)
            #else
            Text(language.text("System sharing is available in the iPhone app.", "系统分享仅在 iPhone App 中可用。"))
                .padding()
            #endif
        }
        .alert(language.text("Export could not be prepared", "无法准备导出文件"), isPresented: $showsExportError) {
            Button(language.text("OK", "好"), role: .cancel) {}
        } message: {
            Text(language.text(
                "The temporary file was not retained. Please try again.",
                "临时文件未被保留，请重试。"
            ))
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text("Metadata", "记录概览")).font(.headline)
            row(language.text("Source", "来源"), sourceText)
            row(language.text("Start", "开始时间"), startDateText)
            row(language.text("Duration", "时长"), language.text(
                String(format: "%.1f s", viewModel.record.durationSeconds),
                String(format: "%.1f 秒", viewModel.record.durationSeconds)
            ))
            row(language.text("Apple classification", "Apple 分类"), appleClassificationText)
            row(language.text("Average heart rate", "平均心率"), heartRateText)
            row(language.text("Sampling frequency", "采样频率"), samplingText)
            row(language.text("Declared measurements", "声明测量数"), "\(viewModel.record.declaredMeasurementCount)")
            row(language.text("Symptoms", "症状"), symptomsText)
        }
        .watchBeatCard()
    }

    @ViewBuilder
    private var stateSection: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView(language.text("Loading voltage measurements…", "正在载入电压测量值…"))
        case .loaded(let measurement):
            loadedSections(measurement: measurement, incomplete: false)
        case .loadedWithIncompleteMeasurements(let measurement):
            loadedSections(measurement: measurement, incomplete: true)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(language.text("Measurement query failed", "测量值查询失败")).font(.headline)
                Text(language.text("Error: \(message)", "错误：\(message)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(language.text("Try again", "重试")) { Task { await viewModel.load() } }
            }
        }
    }

    private func loadedSections(measurement: ECGMeasurement, incomplete: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if measurement.source == .builtInSyntheticExample {
                VStack(alignment: .leading, spacing: 4) {
                    Label(language.text("Built-in synthetic example", "内置合成示例"), systemImage: "testtube.2")
                        .font(.headline)
                    Text(language.text(
                        "Generated for learning the app. This is not a person's ECG and cannot validate medical accuracy.",
                        "该波形仅用于学习应用操作，不属于任何人的心电数据，也不能验证医疗准确性。"
                    ))
                        .font(.caption)
                }
                .foregroundStyle(.orange)
            }
            ECGWaveformView(signal: measurement.signal, markers: viewModel.waveformMarkers)
                .watchBeatCard()
            integritySection(measurement: measurement, incomplete: incomplete)
            exportSection
        }
    }

    private func integritySection(measurement: ECGMeasurement, incomplete: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text("Measurements", "测量完整性")).font(.headline)
            row(language.text("Loaded samples", "已载入采样点"), "\(measurement.integrity.sampleCount)")
            row(language.text("Missing voltages", "缺失电压"), "\(measurement.integrity.missingVoltageIndices.count)")
            row(language.text("Nominal rate", "标称采样率"), rateText(measurement.signal.nominalSamplingRateHz))
            row(language.text("Inferred rate", "推算采样率"), rateText(measurement.integrity.inferredSamplingRateHz))
            row(
                language.text("Timestamps strictly increasing", "时间戳严格递增"),
                measurement.integrity.hasStrictlyIncreasingFiniteTimestamps
                    ? language.text("yes", "是")
                    : language.text("no", "否")
            )

            if incomplete {
                Text(language.text("Incomplete measurement data", "测量数据不完整"))
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.orange)
                ForEach(measurement.issues, id: \.self) { issue in
                    Text("· \(issueText(issue))")
                        .font(.caption)
                }
            }

            Text(language.text(
                "Beat analysis is not implemented yet; the waveform display does not classify beats.",
                "心搏分析尚未实现；波形显示不会对心搏进行分类。"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .watchBeatCard()
    }

    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(language.text("Research use only — not a diagnosis", "仅供研究使用—不构成诊断")).font(.headline)
            Text(language.text(MedicalDisclaimer.english, MedicalDisclaimer.chinese)).font(.caption)
        }
        .watchBeatCard()
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.text("Export", "导出")).font(.headline)
            Label(
                exportNoticeText,
                systemImage: viewModel.source == .healthKit ? "lock.shield" : "testtube.2"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button(language.text("Share raw CSV", "分享原始 CSV")) {
                    pendingExportKind = .rawCSV
                }
                .buttonStyle(.borderedProminent)

                Button(language.text("Share metadata JSON", "分享元数据 JSON")) {
                    pendingExportKind = .metadataJSON
                }
                .buttonStyle(.bordered)
            }
        }
        .watchBeatCard()
    }

    private var showsExportConfirmation: Binding<Bool> {
        Binding(
            get: { pendingExportKind != nil },
            set: { isPresented in
                if !isPresented { pendingExportKind = nil }
            }
        )
    }

    private var sourceText: String {
        switch viewModel.source {
        case .healthKit: return language.text("Apple Health", "Apple 健康")
        case .builtInSyntheticExample: return language.text("Built-in synthetic example", "内置合成示例")
        }
    }

    private var startDateText: String {
        guard viewModel.source == .healthKit else { return language.text("not applicable", "不适用") }
        return viewModel.record.startDate.formatted(date: .abbreviated, time: .standard)
    }

    private var appleClassificationText: String {
        guard viewModel.source == .healthKit else { return language.text("not applicable", "不适用") }
        return classificationText(viewModel.record.classification)
    }

    private var symptomsText: String {
        guard viewModel.source == .healthKit else { return language.text("not applicable", "不适用") }
        switch viewModel.record.symptomsStatus {
        case .notSet: return language.text("Not Set", "未设置")
        case .none: return language.text("None", "无")
        case .present: return language.text("Present", "有")
        }
    }

    private var exportNoticeText: String {
        if viewModel.source == .builtInSyntheticExample {
            return language.text(
                "This example is generated and contains no personal Health data.",
                "此示例由程序生成，不包含个人健康数据。"
            )
        }
        return language.text(
            "Exports contain sensitive health data. Share only with people and apps you trust.",
            "导出文件包含敏感健康数据，请仅分享给你信任的人和应用。"
        )
    }

    private var exportConfirmationTitle: String {
        viewModel.source == .builtInSyntheticExample
            ? language.text("Share the synthetic example?", "分享合成示例？")
            : language.text("This export contains sensitive health data", "此导出包含敏感健康数据")
    }

    private var exportConfirmationMessage: String {
        if viewModel.source == .builtInSyntheticExample {
            return language.text(
                "The file is generated example data and is clearly labelled as synthetic.",
                "该文件是生成的示例数据，并已明确标记为合成数据。"
            )
        }
        return language.text(
            "Anyone you share it with may keep a copy. No file is created until you continue.",
            "接收方可能会保留副本；只有继续后才会创建临时文件。"
        )
    }

    private func prepareExport(kind: ECGExportKind) {
        guard let measurement = viewModel.measurement else { return }
        do {
            sharedExport = try ECGTemporaryExportWriter.create(
                kind: kind,
                measurement: measurement
            )
        } catch {
            showsExportError = true
        }
        pendingExportKind = nil
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private var heartRateText: String {
        guard let heartRate = viewModel.record.averageHeartRateBPM else { return language.text("not available", "不可用") }
        return String(format: "%.0f BPM", heartRate)
    }

    private var samplingText: String {
        guard let rate = viewModel.record.samplingFrequencyHz else { return language.text("not available", "不可用") }
        return String(format: "%.0f Hz", rate)
    }

    private func rateText(_ rate: Double?) -> String {
        guard let rate else { return language.text("not available", "不可用") }
        return String(format: "%.1f Hz", rate)
    }

    private func classificationText(_ classification: ECGAppleClassification) -> String {
        switch classification {
        case .notSet: return language.text("Not Set", "未设置")
        case .sinusRhythm: return language.text("Sinus Rhythm", "窦性心律")
        case .atrialFibrillation: return language.text("Atrial Fibrillation", "房颤")
        case .inconclusiveLowHeartRate: return language.text("Inconclusive — Low Heart Rate", "无法判定—心率过低")
        case .inconclusiveHighHeartRate: return language.text("Inconclusive — High Heart Rate", "无法判定—心率过高")
        case .inconclusivePoorReading: return language.text("Inconclusive — Poor Reading", "无法判定—记录质量不佳")
        case .inconclusiveOther: return language.text("Inconclusive — Other", "无法判定—其他原因")
        case .unrecognized: return language.text("Unrecognized", "无法识别")
        }
    }

    private func issueText(_ issue: ECGMeasurementIssue) -> String {
        switch issue {
        case .noMeasurements: return language.text("No voltage measurements were returned.", "未返回电压测量值。")
        case .missingLeadVoltage: return language.text("Some measurements have no Lead I voltage.", "部分测量缺少 I 导联电压。")
        case .declaredCountMismatch: return language.text("Returned count differs from the declared count.", "返回数量与声明数量不一致。")
        case .nonIncreasingTimeOrder: return language.text("Timestamps are not strictly increasing.", "时间戳未严格递增。")
        case .nonFiniteValue: return language.text("A measurement contains a non-finite value.", "测量中包含非有限值。")
        case .integrityCheckFailed: return language.text("Structural integrity check failed.", "结构完整性检查失败。")
        }
    }
}
