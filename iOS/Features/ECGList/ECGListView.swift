import SwiftUI
import WatchBeatModels

public struct ECGListView: View {
    @AppStorage("hasRequestedECGReadAccess") private var hasRequestedReadAccess = false
    @Bindable var viewModel: ECGListViewModel
    let exampleMeasurement: ECGMeasurement?
    @Environment(\.appLanguage) private var language
    @Environment(ECGAnnotationStore.self) private var annotations

    public init(viewModel: ECGListViewModel, exampleMeasurement: ECGMeasurement? = nil) {
        self.viewModel = viewModel
        self.exampleMeasurement = exampleMeasurement
    }

    public var body: some View {
        ZStack {
            WatchBeatBackground()
            content
        }
        .navigationTitle(language.text("ECG Data", "心电数据"))
        .onAppear { viewModel.startScreeningIfNeeded() }
        .toolbar {
            if viewModel.canReload {
                ToolbarItem(placement: .primaryAction) {
                    Button(language.text("Reload", "重新载入")) {
                        Task { await viewModel.load() }
                    }
                }
            }
        }
        .navigationDestination(for: ECGRecord.self) { record in
            ECGDetailView(viewModel: viewModel.makeDetailViewModel(for: record))
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let exampleMeasurement {
                    NavigationLink {
                        ECGDetailView(viewModel: ECGDetailViewModel(example: exampleMeasurement))
                    } label: {
                        ECGExampleRecordRow(measurement: exampleMeasurement)
                            .watchBeatDataCard()
                    }
                    .buttonStyle(.plain)
                }

                Text(language.text("Apple Health ECG", "Apple 健康 ECG"))
                    .font(.headline)
                    .padding(.top, 4)

                healthKitContent
            }
            .padding()
        }
    }

    @ViewBuilder
    private var healthKitContent: some View {
        switch viewModel.state {
        case .idle, .loading:
            healthStatusCard(
                symbol: "arrow.triangle.2.circlepath",
                title: language.text("Loading Apple Health ECG…", "正在载入 Apple 健康 ECG…"),
                message: language.text(
                    "The example data above is ready while HealthKit metadata loads.",
                    "HealthKit 元数据载入期间，上方的示例数据仍可使用。"
                )
            ) {
                ProgressView()
            }
        case .unavailable:
            healthStatusCard(
                symbol: "heart.slash",
                title: language.text("HealthKit ECG is unavailable", "HealthKit 心电不可用"),
                message: language.text(
                    "This device or OS version does not expose ECG records through HealthKit.",
                    "此设备或系统版本未通过 HealthKit 提供心电记录。"
                )
            )
        case .authorizationRequired:
            healthStatusCard(
                symbol: "lock.shield",
                title: language.text("ECG read access has not been requested", "尚未申请心电读取权限"),
                message: language.text(
                    "Only reading saved ECG records is requested. Nothing is written to Apple Health.",
                    "应用只申请读取已保存的心电记录，不会向 Apple 健康写入任何内容。"
                )
            ) {
                Button(language.text("Request ECG read access", "申请心电读取权限")) {
                    Task { await requestReadAccess() }
                }
                .buttonStyle(.borderedProminent)
            }
        case .noAccessibleRecords:
            healthStatusCard(
                symbol: "waveform.path.ecg",
                title: language.text("No accessible Apple Health ECG", "没有可访问的 Apple 健康 ECG"),
                message: language.text("""
                    No ECG record was returned. This can mean no saved Apple Watch ECG exists, or that \
                    read access was not granted. HealthKit does not allow these to be distinguished.
                    """, "没有返回心电记录。这可能表示尚无 Apple Watch 心电记录，也可能表示未授予读取权限；HealthKit 不允许应用区分这两种情况。")
            ) {
                Button(language.text("Request access again", "再次申请读取权限")) {
                    Task { await requestReadAccess() }
                }
                .buttonStyle(.bordered)
            }
        case .loaded(let records):
            let matches = filteredRecords
            ECGRecordFilterView(filter: $viewModel.filter, availableTags: availableTags)
            if annotations.hasLoadFailure {
                Text(language.text("Saved annotations are unavailable; tag and note searches may be incomplete.", "已保存的批注暂不可用，标签与文字搜索可能不完整。"))
                    .font(.caption).foregroundStyle(.orange)
                Button(language.text("Retry annotations", "重试读取批注")) { annotations.reload() }
            }
            Text(language.text("\(matches.count) of \(records.count) recordings", "匹配 \(matches.count) / \(records.count) 条记录"))
                .font(.subheadline).foregroundStyle(.secondary)
            Label(
                language.text(
                    "Records are screened one by one on this device; badges are research flags, not diagnoses.",
                    "记录会在本机逐条筛查；列表标识仅供研究参考，不是诊断。"
                ),
                systemImage: "iphone"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if matches.isEmpty {
                healthStatusCard(
                    symbol: "magnifyingglass",
                    title: language.text("No matching recordings", "没有匹配的记录"),
                    message: language.text("Try a wider date range or reset the filters. Analysis-result matches update as screening completes.", "可扩大日期范围或重置筛选；分析结果筛选会随筛查完成而更新。")
                ) {
                    Button(language.text("Reset filters", "重置筛选")) { viewModel.filter = ECGRecordFilter() }
                }
            }
            ForEach(matches) { record in
                NavigationLink(value: record) {
                    ECGRecordRow(
                        record: record,
                        screeningState: viewModel.screeningState(for: record),
                        annotation: annotations.annotation(for: record.id)
                    )
                    .watchBeatDataCard(
                        isFlagged: viewModel.screeningState(for: record)?.isFlagged == true
                    )
                }
                .buttonStyle(.plain)
            }
        case .failed(let message):
            healthStatusCard(
                symbol: "exclamationmark.triangle",
                title: language.text("Unable to access ECG records", "无法访问心电记录"),
                message: language.text("Error: \(message)", "错误：\(message)")
            ) {
                Button(language.text("Try again", "重试")) {
                    Task { await requestReadAccess() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var availableTags: [ECGRecordTag] {
        Array(Set(viewModel.records.flatMap { annotations.annotation(for: $0.id).tags }))
            .sorted { $0.id < $1.id }
    }

    private var filteredRecords: [ECGRecord] {
        let now = Date()
        return viewModel.records.filter { record in
            let annotation = annotations.annotation(for: record.id)
            let titles = annotation.tags.flatMap { [$0.title(in: .english), $0.title(in: .simplifiedChinese)] }
            return viewModel.filter.matches(
                record, annotation: annotation, screening: viewModel.screeningState(for: record),
                now: now, searchTerms: titles
            )
        }
    }

    private func healthStatusCard(
        symbol: String,
        title: String,
        message: String,
        @ViewBuilder action: () -> some View = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            action()
        }
        .watchBeatCard()
    }

    @MainActor
    private func requestReadAccess() async {
        if await viewModel.requestReadAccess() {
            hasRequestedReadAccess = true
        }
    }
}

public struct ECGExampleRecordRow: View {
    let measurement: ECGMeasurement
    @Environment(\.appLanguage) private var language

    public init(measurement: ECGMeasurement) {
        self.measurement = measurement
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 46, height: 46)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(language.text("Example ECG Data", "示例 ECG 数据"))
                        .font(.headline)
                    Text(language.text("SYNTHETIC", "合成"))
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }

                Text(language.text(
                    "Built into the app; contains no personal health data",
                    "App 内置，不包含个人健康数据"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    metricText(heartRateText)
                    metricText(durationText)
                    metricText(language.text(
                        "\(measurement.integrity.sampleCount) samples",
                        "\(measurement.integrity.sampleCount) 点"
                    ))
                }

                if case .prematureCandidates(let count) = measurement.screeningSummary {
                    Label(
                        language.text(
                            "Demo: \(count) premature candidate(s)",
                            "演示波形：\(count) 个疑似早搏候选"
                        ),
                        systemImage: "flag.fill"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(Color.watchBeatAttentionText)
                }
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(language.text("Opens the example ECG waveform", "打开示例 ECG 波形"))
    }

    private var heartRateText: String {
        guard let heartRate = measurement.record.averageHeartRateBPM else { return "—" }
        return "\(Int(heartRate.rounded())) BPM"
    }

    private var durationText: String {
        language.text(
            String(format: "%.1f s", measurement.record.durationSeconds),
            String(format: "%.1f 秒", measurement.record.durationSeconds)
        )
    }

    private func metricText(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

public struct ECGRecordRow: View {
    let record: ECGRecord
    let screeningState: ECGListScreeningState?
    let annotation: ECGAnnotation
    @Environment(\.appLanguage) private var language

    public init(record: ECGRecord, screeningState: ECGListScreeningState? = nil, annotation: ECGAnnotation = ECGAnnotation()) {
        self.record = record
        self.screeningState = screeningState
        self.annotation = annotation
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.title3)
                .foregroundStyle(isFlagged ? Color.watchBeatAttentionText : Color.secondary)
                .frame(width: 42, height: 42)
                .background(
                    isFlagged ? Color.watchBeatAttention.opacity(0.2) : Color.secondary.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 12)
                )

            VStack(alignment: .leading, spacing: 7) {
                Text(record.startDate, format: .dateTime.year().month().day().hour().minute())
                    .font(.headline)
                Text(language.text("Apple: \(classificationText)", "Apple 分类：\(classificationText)"))
                    .font(.subheadline)
                Text(language.text(
                    "\(String(format: "%.1f", record.durationSeconds)) s · \(record.declaredMeasurementCount) measurements",
                    "\(String(format: "%.1f", record.durationSeconds)) 秒 · \(record.declaredMeasurementCount) 个测量值"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                screeningBadge
                ECGAnnotationTags(tags: annotation.tags)
                if !annotation.note.isEmpty {
                    Label(annotation.note, systemImage: "text.bubble")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint(language.text("Opens this ECG waveform", "打开这条 ECG 波形"))
    }

    private var isFlagged: Bool {
        screeningState?.isFlagged == true
    }

    @ViewBuilder
    private var screeningBadge: some View {
        if let screeningState {
            switch screeningState {
            case .checking:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(language.text("Screening on device…", "正在本机筛查…"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            case .result(.noPrematureCandidates):
                // The Apple classification above remains the source of rhythm wording.
                EmptyView()
            case .result(.prematureCandidates(let count)):
                badge(
                    language.text(
                        "\(count) premature candidate(s) to review",
                        "\(count) 处疑似早搏候选，可点开查看"
                    ),
                    symbol: "flag.fill",
                    tint: .watchBeatAttentionText,
                    background: .watchBeatAttention
                )
            case .result(.notAnalyzed):
                badge(
                    language.text("Unable to analyze this recording", "这条记录无法分析"),
                    symbol: "questionmark.circle.fill",
                    tint: .secondary
                )
            case .failed:
                badge(
                    language.text("Screening failed — open for details", "筛查失败—可点开查看"),
                    symbol: "exclamationmark.circle.fill",
                    tint: .orange
                )
            }
        }
    }

    private func badge(
        _ text: String,
        symbol: String,
        tint: Color,
        background: Color? = nil
    ) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.bold())
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                background.map { $0.opacity(0.22) } ?? tint.opacity(0.1),
                in: Capsule()
            )
    }

    private var classificationText: String {
        switch record.classification {
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
}
