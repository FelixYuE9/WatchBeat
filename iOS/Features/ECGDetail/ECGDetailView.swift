import SwiftUI
import WatchBeatModels

public struct ECGDetailView: View {
    @State private var viewModel: ECGDetailViewModel
    @State private var pendingExportKind: ECGExportKind?
    @State private var sharedExport: ECGTemporaryExportFile?
    @State private var showsExportError = false
    @State private var waveformFocusRequest: ECGWaveformFocusRequest?
    @State private var showsTechnicalDetails = false
    @Environment(\.appLanguage) private var language

    private let waveformCardID = "watchbeat.detail.waveform"

    public init(viewModel: ECGDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ZStack {
            WatchBeatBackground()
            ScrollViewReader { pageProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection
                        stateSection(pageProxy: pageProxy)
                        ECGAnnotationView(record: viewModel.record, source: viewModel.source)
                        if viewModel.measurement != nil {
                            exportSection
                        }
                        technicalSection
                        disclaimerSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle(language.text("ECG Record", "心电图详情"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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

    // MARK: - Header

    /// What a person reading their own recording looks for first: when, how long, the rate and
    /// whether anything was flagged. Acquisition details are in the technical section at the bottom.
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                headerTitle
                    .font(.title2.bold())
                Text(sourceText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                WatchBeatMetricTile(
                    value: heartRateTileText,
                    label: language.text("Average heart rate", "平均心率")
                )
                WatchBeatMetricTile(
                    value: language.text(
                        String(format: "%.1f s", viewModel.record.durationSeconds),
                        String(format: "%.1f 秒", viewModel.record.durationSeconds)
                    ),
                    label: language.text("Duration", "时长")
                )
                WatchBeatMetricTile(
                    value: candidateCount.map { "\($0)" } ?? "—",
                    label: language.text("Premature candidates", "疑似早搏候选"),
                    isHighlighted: (candidateCount ?? 0) > 0
                )
            }
            .fixedSize(horizontal: false, vertical: true)

            if viewModel.source == .healthKit {
                Divider()
                VStack(spacing: 8) {
                    ECGInfoRow(language.text("Apple classification", "Apple 分类"), appleClassificationText)
                    ECGInfoRow(language.text("Apple-recorded symptoms", "Apple 记录的症状"), symptomsText)
                }
            }
        }
        .watchBeatPanel()
    }

    @ViewBuilder
    private var headerTitle: some View {
        if viewModel.source == .healthKit {
            Text(viewModel.record.startDate, format: .dateTime.year().month().day().hour().minute())
        } else {
            Text(language.text("Example ECG Data", "示例 ECG 数据"))
        }
    }

    /// `nil` until the report is loaded, or when the recording could not be analyzed.
    private var candidateCount: Int? {
        guard let measurement = viewModel.measurement, measurement.analysis.status == .analyzed else {
            return nil
        }
        return measurement.analysis.summary.prematureCandidateCount
    }

    // MARK: - Loaded content

    @ViewBuilder
    private func stateSection(pageProxy: ScrollViewProxy) -> some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView(language.text("Loading voltage measurements…", "正在载入电压测量值…"))
                .frame(maxWidth: .infinity, minHeight: 200)
                .watchBeatPanel()
        case .loaded(let measurement):
            loadedSections(measurement: measurement, incomplete: false, pageProxy: pageProxy)
        case .loadedWithIncompleteMeasurements(let measurement):
            loadedSections(measurement: measurement, incomplete: true, pageProxy: pageProxy)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                WatchBeatSectionTitle(
                    language.text("Measurement query failed", "测量值查询失败"),
                    systemImage: "exclamationmark.triangle"
                )
                Text(language.text("Error: \(message)", "错误：\(message)"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(language.text("Try again", "重试")) { Task { await viewModel.load() } }
                    .buttonStyle(.bordered)
            }
            .watchBeatPanel()
        }
    }

    private func loadedSections(
        measurement: ECGMeasurement,
        incomplete: Bool,
        pageProxy: ScrollViewProxy
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if measurement.source == .builtInSyntheticExample || incomplete {
                VStack(alignment: .leading, spacing: 8) {
                    if measurement.source == .builtInSyntheticExample {
                        notice(
                            language.text("Built-in synthetic example", "内置合成示例"),
                            detail: language.text(
                                "Generated for learning the app. This is not a person's ECG and cannot validate medical accuracy.",
                                "该波形仅用于学习应用操作，不属于任何人的心电数据，也不能验证医疗准确性。"
                            ),
                            systemImage: "testtube.2"
                        )
                    }
                    if incomplete {
                        notice(
                            language.text("Some measurement data is incomplete", "部分测量数据不完整"),
                            detail: language.text(
                                "See Technical details at the bottom.",
                                "详见页面底部的“技术详情”。"
                            ),
                            systemImage: "exclamationmark.circle"
                        )
                    }
                }
            }
            ECGWaveformView(
                signal: measurement.signal,
                markers: viewModel.waveformMarkers,
                focusRequest: $waveformFocusRequest
            )
            .watchBeatPanel()
            .id(waveformCardID)
            ECGAnalysisResultView(
                report: measurement.analysis,
                onSelectCandidate: { timeSeconds in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        pageProxy.scrollTo(waveformCardID, anchor: .top)
                    }
                    waveformFocusRequest = ECGWaveformFocusRequest(timeSeconds: timeSeconds)
                }
            )
        }
    }

    private func notice(_ title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Export

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            WatchBeatSectionTitle(language.text("Export", "导出"), systemImage: "square.and.arrow.up")
            VStack(spacing: 0) {
                exportRow(
                    .analysisJSON,
                    title: language.text("Analysis results", "分析结果"),
                    detail: language.text("JSON · candidates, rate and parameters", "JSON · 候选、心率与参数"),
                    symbol: "doc.text"
                )
                Divider().padding(.leading, 44)
                exportRow(
                    .rawCSV,
                    title: language.text("Raw waveform", "原始波形"),
                    detail: language.text("CSV · full-resolution voltage samples", "CSV · 全分辨率电压采样"),
                    symbol: "tablecells"
                )
                Divider().padding(.leading, 44)
                exportRow(
                    .metadataJSON,
                    title: language.text("Recording metadata", "记录元数据"),
                    detail: language.text("JSON · acquisition details", "JSON · 采集信息"),
                    symbol: "list.bullet.rectangle"
                )
            }
            Label(
                exportNoticeText,
                systemImage: viewModel.source == .healthKit ? "lock.shield" : "testtube.2"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .watchBeatPanel()
    }

    private func exportRow(_ kind: ECGExportKind, title: String, detail: String, symbol: String) -> some View {
        Button {
            pendingExportKind = kind
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.text("Share \(title)", "分享\(title)"))
    }

    // MARK: - Technical details and disclaimer

    /// Analysis provenance, acquisition metadata and integrity facts for professionals. Collapsed
    /// by default and kept near the bottom of the page.
    private var technicalSection: some View {
        DisclosureGroup(isExpanded: $showsTechnicalDetails) {
            VStack(alignment: .leading, spacing: 14) {
                if let measurement = viewModel.measurement {
                    ECGAnalysisTechnicalDetails(
                        report: measurement.analysis,
                        analysisDurationSeconds: measurement.analysisDurationSeconds
                    )
                    Divider()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(language.text("Recording metadata", "记录元数据"))
                        .font(.subheadline.bold())
                    ECGInfoRow(language.text("Source", "来源"), sourceText)
                    if viewModel.source == .healthKit {
                        ECGInfoRow(language.text("Start", "开始时间"), startDateText)
                    }
                    ECGInfoRow(language.text("Sampling frequency", "采样频率"), samplingText)
                    ECGInfoRow(
                        language.text("Declared measurements", "声明测量数"),
                        "\(viewModel.record.declaredMeasurementCount)"
                    )
                }
                if let measurement = viewModel.measurement {
                    Divider()
                    integrityContent(measurement: measurement)
                }
            }
            .padding(.top, 12)
        } label: {
            Label(
                language.text("Technical details (for professionals)", "技术详情（供专业人员参考）"),
                systemImage: "wrench.and.screwdriver"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .watchBeatPanel()
    }

    private func integrityContent(measurement: ECGMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text("Measurement integrity", "测量完整性")).font(.subheadline.bold())
            ECGInfoRow(language.text("Loaded samples", "已载入采样点"), "\(measurement.integrity.sampleCount)")
            ECGInfoRow(
                language.text("Missing voltages", "缺失电压"),
                "\(measurement.integrity.missingVoltageIndices.count)"
            )
            ECGInfoRow(language.text("Nominal rate", "标称采样率"), rateText(measurement.signal.nominalSamplingRateHz))
            ECGInfoRow(language.text("Inferred rate", "推算采样率"), rateText(measurement.integrity.inferredSamplingRateHz))
            ECGInfoRow(
                language.text("Timestamps strictly increasing", "时间戳严格递增"),
                measurement.integrity.hasStrictlyIncreasingFiniteTimestamps
                    ? language.text("yes", "是")
                    : language.text("no", "否")
            )

            if !measurement.isComplete {
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
                "The original full-resolution samples above are the exact samples passed to the " +
                    "model; display downsampling never changes model input.",
                "上方完整分辨率原始采样就是传入模型的数据；显示降采样不会改变模型输入。"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Required on every result page; kept as a quiet footer rather than another card.
    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                language.text("Research use only — not a diagnosis", "仅供研究使用，不构成诊断"),
                systemImage: "info.circle"
            )
            .font(.footnote.weight(.semibold))
            Text(language.text(
                "Screening results cannot diagnose or rule out an arrhythmia.",
                "筛查结果不能用于诊断或排除心律失常。"
            ))
            Text(language.text(MedicalDisclaimer.english, MedicalDisclaimer.chinese))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
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
        return viewModel.record.classification.title(in: language)
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

    private var heartRateTileText: String {
        guard let heartRate = viewModel.record.averageHeartRateBPM else { return "—" }
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
