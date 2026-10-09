import SwiftUI
import WatchBeatModels

extension ECGAppleClassification {
    func title(in language: AppLanguage) -> String {
        switch self {
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

/// Records of one calendar month, in the repository's order.
private struct ECGRecordMonth: Identifiable {
    let month: Date
    var records: [ECGRecord]
    var id: Date { month }

    static func group(_ records: [ECGRecord], calendar: Calendar = .current) -> [ECGRecordMonth] {
        var months: [ECGRecordMonth] = []
        for record in records {
            let month = calendar.dateInterval(of: .month, for: record.startDate)?.start
                ?? calendar.startOfDay(for: record.startDate)
            if let last = months.indices.last, months[last].month == month {
                months[last].records.append(record)
            } else if let existing = months.firstIndex(where: { $0.month == month }) {
                months[existing].records.append(record)
            } else {
                months.append(ECGRecordMonth(month: month, records: [record]))
            }
        }
        return months
    }
}

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
                    Button {
                        Task { await viewModel.load() }
                    } label: {
                        Label(language.text("Reload", "重新载入"), systemImage: "arrow.clockwise")
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
                if case .loaded(let records) = viewModel.state {
                    loadedContent(records)
                    exampleSection
                } else {
                    healthKitStatus
                    exampleSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Loaded records

    @ViewBuilder
    private func loadedContent(_ records: [ECGRecord]) -> some View {
        let matches = filteredRecords

        ECGRecordFilterBar(filter: $viewModel.filter, availableTags: availableTags)

        if annotations.hasLoadFailure {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(language.text(
                    "Saved annotations are unavailable; tag and note searches may be incomplete.",
                    "已保存的批注暂不可用，标签与文字搜索可能不完整。"
                ))
                .font(.caption)
                Spacer(minLength: 4)
                Button(language.text("Retry", "重试")) { annotations.reload() }
                    .font(.caption.weight(.semibold))
            }
            .padding(12)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }

        resultSummary(matches: matches.count, total: records.count)

        if matches.isEmpty {
            noMatchesCard
        } else {
            ForEach(ECGRecordMonth.group(matches)) { month in
                monthHeader(month)
                ForEach(month.records) { record in
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
            }
        }

        WatchBeatFootnote(
            text: language.text(
                "Records are screened one by one on this device; yellow flags are research marks, not diagnoses.",
                "记录会在本机逐条筛查；黄色标识仅供研究参考，不是诊断。"
            ),
            systemImage: "iphone"
        )
        .padding(.top, 4)
    }

    /// Match count on the left, on-device screening progress on the right.
    private func resultSummary(matches: Int, total: Int) -> some View {
        HStack(spacing: 8) {
            Text(language.text("\(matches) of \(total) recordings", "匹配 \(matches) / \(total) 条记录"))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Spacer(minLength: 8)
            let pending = pendingScreeningCount
            if pending > 0 {
                ProgressView()
                    .controlSize(.mini)
                Text(language.text(
                    "Screening \(total - pending)/\(total)",
                    "本机筛查 \(total - pending)/\(total)"
                ))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }

    private func monthHeader(_ month: ECGRecordMonth) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(month.month, format: .dateTime.year().month(.wide))
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text(language.text("\(month.records.count) recordings", "\(month.records.count) 条"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.top, 10)
        .accessibilityAddTraits(.isHeader)
    }

    private var noMatchesCard: some View {
        ECGEmptyStateCard(
            symbol: "magnifyingglass",
            title: language.text("No matching recordings", "没有匹配的记录"),
            message: language.text(
                "Try a wider date range or reset the filters. Analysis-result matches update as screening completes.",
                "可扩大日期范围或重置筛选；分析结果筛选会随筛查完成而更新。"
            )
        ) {
            Button(language.text("Reset filters", "重置筛选")) { viewModel.filter = ECGRecordFilter() }
                .buttonStyle(.bordered)
        }
    }

    // MARK: - HealthKit states

    @ViewBuilder
    private var healthKitStatus: some View {
        switch viewModel.state {
        case .idle, .loading:
            ECGEmptyStateCard(
                symbol: "arrow.triangle.2.circlepath",
                title: language.text("Loading Apple Health ECG…", "正在载入 Apple 健康 ECG…"),
                message: language.text(
                    "The example below is ready while HealthKit metadata loads.",
                    "HealthKit 元数据载入期间，可以先查看下方的示例数据。"
                )
            ) {
                ProgressView()
            }
        case .unavailable:
            ECGEmptyStateCard(
                symbol: "heart.slash",
                title: language.text("HealthKit ECG is unavailable", "HealthKit 心电不可用"),
                message: language.text(
                    "This device or OS version does not expose ECG records through HealthKit.",
                    "此设备或系统版本未通过 HealthKit 提供心电记录。"
                )
            )
        case .authorizationRequired:
            ECGEmptyStateCard(
                symbol: "lock.shield",
                title: language.text("ECG read access has not been requested", "尚未申请心电读取权限"),
                message: language.text(
                    "Only reading saved ECG records is requested. Nothing is written to Apple Health.",
                    "应用只申请读取已保存的心电记录，不会向 Apple 健康写入任何内容。"
                )
            ) {
                Button {
                    Task { await requestReadAccess() }
                } label: {
                    Text(language.text("Request ECG read access", "申请心电读取权限"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        case .noAccessibleRecords:
            ECGEmptyStateCard(
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
        case .loaded:
            EmptyView()
        case .failed(let message):
            ECGEmptyStateCard(
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

    // MARK: - Example

    @ViewBuilder
    private var exampleSection: some View {
        if let exampleMeasurement {
            Text(language.text("Built-in example", "内置示例"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, 14)
                .accessibilityAddTraits(.isHeader)
            NavigationLink {
                ECGDetailView(viewModel: ECGDetailViewModel(example: exampleMeasurement))
            } label: {
                ECGExampleRecordRow(measurement: exampleMeasurement)
                    .watchBeatPanel()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var pendingScreeningCount: Int {
        viewModel.records.filter { record in
            let state = viewModel.screeningState(for: record)
            return state == nil || state == .checking
        }.count
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

    @MainActor
    private func requestReadAccess() async {
        if await viewModel.requestReadAccess() {
            hasRequestedReadAccess = true
        }
    }
}

/// Centered icon, title, message and an optional action; used for empty and HealthKit states.
struct ECGEmptyStateCard<Action: View>: View {
    let symbol: String
    let title: String
    let message: String
    let action: Action

    init(symbol: String, title: String, message: String, @ViewBuilder action: () -> Action) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.action = action()
    }

    var body: some View {
        VStack(spacing: 12) {
            WatchBeatIconBadge(systemImage: symbol, size: 52)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            action
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .watchBeatPanel()
    }
}

extension ECGEmptyStateCard where Action == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

public struct ECGExampleRecordRow: View {
    let measurement: ECGMeasurement
    @Environment(\.appLanguage) private var language

    public init(measurement: ECGMeasurement) {
        self.measurement = measurement
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            WatchBeatIconBadge(systemImage: "testtube.2", tint: .orange, size: 44)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(language.text("Example ECG Data", "示例 ECG 数据"))
                        .font(.headline)
                    Text(language.text("SYNTHETIC", "合成"))
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }

                Text(language.text(
                    "Built into the app; contains no personal health data",
                    "App 内置，不包含个人健康数据"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Text(heartRateText)
                    Text("·")
                    Text(durationText)
                    if case .prematureCandidates(let count) = measurement.screeningSummary {
                        Text("·")
                        Label(
                            language.text("\(count) demo candidate(s)", "\(count) 个演示候选"),
                            systemImage: "flag.fill"
                        )
                        .foregroundStyle(Color.watchBeatAttentionText)
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
            String(format: "%.0f s", measurement.record.durationSeconds),
            String(format: "%.0f 秒", measurement.record.durationSeconds)
        )
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
            WatchBeatIconBadge(
                systemImage: "waveform.path.ecg",
                tint: isFlagged ? Color.watchBeatAttentionText : Color.secondary,
                background: isFlagged ? Color.watchBeatAttention.opacity(0.2) : Color.watchBeatInset,
                size: 40
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(record.startDate, format: .dateTime.month().day().weekday(.abbreviated).hour().minute())
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    heartRate
                }

                Text("\(record.classification.title(in: language)) · \(durationText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                screeningBadge

                if !annotation.tags.isEmpty {
                    ECGAnnotationTags(tags: annotation.tags)
                }
                if !annotation.note.isEmpty {
                    Label(annotation.note, systemImage: "text.bubble")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .padding(.top, 5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(language.text("Opens this ECG waveform", "打开这条 ECG 波形"))
    }

    @ViewBuilder
    private var heartRate: some View {
        if let bpm = record.averageHeartRateBPM, bpm.isFinite, bpm > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(bpm.rounded()))")
                    .font(.headline.monospacedDigit())
                Text("BPM")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isFlagged: Bool {
        screeningState?.isFlagged == true
    }

    private var durationText: String {
        language.text(
            String(format: "%.0f s", record.durationSeconds),
            String(format: "%.0f 秒", record.durationSeconds)
        )
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
            .padding(.vertical, 4)
            .background(
                background.map { $0.opacity(0.22) } ?? tint.opacity(0.1),
                in: Capsule()
            )
    }
}
