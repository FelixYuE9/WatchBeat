import Charts
import SwiftUI
import WatchBeatModels

public struct OverviewView: View {
    let viewModel: ECGListViewModel
    let exampleMeasurement: ECGMeasurement?
    @Binding var selectedTab: AppTab
    @Environment(\.appLanguage) private var language
    @Environment(ECGAnnotationStore.self) private var annotations
    @State private var period = ECGRecordFilter(dateRange: .last30Days)

    public init(
        viewModel: ECGListViewModel,
        exampleMeasurement: ECGMeasurement?,
        selectedTab: Binding<AppTab>
    ) {
        self.viewModel = viewModel
        self.exampleMeasurement = exampleMeasurement
        _selectedTab = selectedTab
    }

    public var body: some View {
        ZStack {
            WatchBeatBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    statusCard
                    if case .loaded = viewModel.state {
                        insightsSection
                    }
                    quickActions
                    safetyNote
                }
                .padding()
            }
        }
        .navigationTitle(language.text("Overview", "概览"))
        .onAppear { viewModel.startScreeningIfNeeded() }
    }

    private var periodRecords: [ECGRecord] {
        let now = Date()
        return viewModel.records.filter { period.contains($0.startDate, now: now) }
    }

    private var groupsByMonth: Bool {
        let dates = periodRecords.map(\.startDate)
        guard let first = dates.min(), let last = dates.max() else { return false }
        return last.timeIntervalSince(first) > 90 * 86_400
    }

    private var insights: ECGRecordInsights {
        ECGRecordInsights(
            records: periodRecords, screening: viewModel.screeningStates,
            annotations: annotations.annotations, groupByMonth: groupsByMonth
        )
    }

    private var insightsSection: some View {
        // A single snapshot is shared by all cards during each render.
        let summary = insights
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Label(language.text("Recording insights", "记录分析"), systemImage: "chart.bar.xaxis")
                    .font(.headline)
                ECGDateRangePicker(filter: $period)
                if summary.recordCount == 0 {
                    Text(language.text("No accessible ECGs in this date range.", "此日期范围内没有可访问的 ECG。"))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 12) {
                        metric(value: "\(summary.recordCount)", label: language.text("Recordings in range", "范围内记录"), symbol: "waveform.path.ecg")
                        metric(
                            value: summary.averageHeartRateBPM.map { "\($0.formatted(.number.precision(.fractionLength(0)))) bpm" } ?? "—",
                            label: language.text("Mean recorded HR", "记录平均心率"), symbol: "heart.fill"
                        )
                    }
                    HStack(spacing: 12) {
                        metric(value: summary.analyzedCount > 0 ? "\(summary.candidateCount)" : "—",
                               label: language.text("Candidates flagged", "标记候选总数"), symbol: "flag")
                        metric(value: annotations.hasLoadFailure ? "—" : "\(summary.annotatedCount)", label: language.text("Annotated records", "有批注的记录"), symbol: "text.bubble")
                    }
                    Text(language.text("Heart-rate mean uses \(summary.heartRateRecordCount) ECG record(s) with a valid Apple average heart rate.", "心率均值来自 \(summary.heartRateRecordCount) 条具有有效 Apple 平均心率的 ECG 记录。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(language.text("Browse this date range", "查看此日期范围的记录")) {
                    viewModel.filter = period
                    selectedTab = .records
                }
                .buttonStyle(.bordered)
            }
            .watchBeatCard()

            if summary.recordCount > 0 {
                screeningDistribution(summary)
                trends(summary)
                tagDistribution(summary)
            }
        }
    }

    private func screeningDistribution(_ summary: ECGRecordInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(language.text("Analysis coverage", "分析覆盖情况"), systemImage: "checkmark.circle")
                .font(.headline)
            Text(language.text("Analyzed \(summary.analyzedCount) / \(summary.recordCount) recordings", "已分析 \(summary.analyzedCount) / \(summary.recordCount) 条记录"))
                .font(.subheadline)
            ProgressView(value: Double(summary.analyzedCount), total: Double(summary.recordCount))
                .tint(.pink)
            countRow(language.text("With candidates", "有疑似候选"), summary.candidateRecordCount)
            countRow(language.text("No candidates flagged", "未标记候选"), summary.analyzedCount - summary.candidateRecordCount)
            countRow(language.text("Unable to analyze", "无法分析"), summary.unableToAnalyzeCount)
            countRow(language.text("Pending analysis", "待分析"), summary.pendingCount)
            countRow(language.text("Read failed", "读取失败"), summary.failedCount)
            Text(language.text("Counts update as on-device screening finishes. These sampled ECGs do not estimate whole-day premature-beat burden.", "统计会随本机筛查完成而更新。短时 ECG 抽样不能用于估算全天早搏负荷。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .watchBeatCard()
    }

    private func trends(_ summary: ECGRecordInsights) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(language.text("Recording trends", "记录趋势"), systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
            Text(language.text(groupsByMonth ? "Recordings per month" : "Recordings per day", groupsByMonth ? "每月记录数" : "每日记录数"))
                .font(.subheadline)
            Chart(summary.buckets) { bucket in
                BarMark(
                    x: .value(language.text("Date", "日期"), bucket.date, unit: groupsByMonth ? .month : .day),
                    y: .value(language.text("Recordings", "记录数"), bucket.recordCount)
                )
                .foregroundStyle(Color.pink.opacity(0.7))
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .frame(height: 150)
            if summary.heartRateRecordCount > 0 {
                Text(language.text("Mean recorded heart rate · bpm", "记录平均心率 · bpm"))
                    .font(.subheadline)
                Chart(summary.buckets) { bucket in
                    if let heartRate = bucket.averageHeartRateBPM {
                        LineMark(x: .value("Date", bucket.date), y: .value("bpm", heartRate))
                            .foregroundStyle(.pink)
                        PointMark(x: .value("Date", bucket.date), y: .value("bpm", heartRate))
                            .foregroundStyle(.pink)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: 150)
            } else {
                Text(language.text("These records have no valid Apple average heart rate to plot.", "这些记录没有可绘制的有效 Apple 平均心率。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(language.text("Only recorded ECGs are summarized; gaps in recording are not continuous monitoring.", "仅汇总实际记录的 ECG；记录间的空白不代表持续监测。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .watchBeatCard()
    }

    private func tagDistribution(_ summary: ECGRecordInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(language.text("Feelings and tags", "感受与标签分布"), systemImage: "tag")
                .font(.headline)
            if annotations.hasLoadFailure {
                Text(language.text("Saved annotations could not be read. Retry to restore tag statistics.", "无法读取已保存的批注，请重试恢复标签统计。"))
                    .font(.caption).foregroundStyle(.orange)
                Button(language.text("Retry", "重试")) { annotations.reload() }
            } else if summary.tagCounts.isEmpty {
                Text(language.text("Add feelings or custom tags in an ECG detail to see their frequency here.", "在 ECG 详情中添加感受或自定义标签后，即可查看出现次数。"))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(summary.tagCounts) { entry in
                    Button {
                        viewModel.filter = period
                        viewModel.filter.tags = [entry.tag]
                        selectedTab = .records
                    } label: {
                        VStack(spacing: 6) {
                            HStack {
                                Text(entry.tag.title(in: language))
                                Spacer()
                                Text(language.text("\(entry.count) recordings", "\(entry.count) 条"))
                                    .monospacedDigit()
                                Image(systemName: "chevron.right").font(.caption)
                            }
                            ProgressView(value: Double(entry.count), total: Double(summary.recordCount)).tint(.pink)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(language.text("Show matching recordings", "查看匹配记录"))
                }
            }
            Text(language.text("Self-reported tags can overlap. Counts describe your notes and do not establish symptom causes.", "自述标签可重叠；次数只描述你的记录，不推断症状原因。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .watchBeatCard()
    }

    private func countRow(_ title: String, _ count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count)").monospacedDigit()
        }
        .font(.subheadline)
    }

    private var hero: some View {
        HStack(spacing: 16) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 34))
                .foregroundStyle(.pink)
                .frame(width: 62, height: 62)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 4) {
                Text("WatchBeat")
                    .font(.largeTitle.bold())
                Text(language.text(
                    "Private, on-device ECG research",
                    "隐私优先的本地心电研究工具"
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                language.text("Your ECG overview", "你的心电概览"),
                systemImage: "chart.line.uptrend.xyaxis"
            )
            .font(.headline)

            HStack(spacing: 12) {
                metric(
                    value: recordCountText,
                    label: language.text("Accessible records", "可访问记录"),
                    symbol: "list.bullet.rectangle"
                )
                metric(
                    value: latestHeartRateText,
                    label: language.text("Latest average HR", "最近平均心率"),
                    symbol: "heart.fill"
                )
            }

            Divider()
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .watchBeatCard()
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text("Start here", "从这里开始"))
                .font(.headline)

            if let exampleMeasurement {
                NavigationLink {
                    ECGDetailView(viewModel: ECGDetailViewModel(example: exampleMeasurement))
                } label: {
                    actionRow(
                        title: language.text("Explore the ECG example", "查看合成心电示例"),
                        subtitle: language.text(
                            "Learn waveform zoom, R–R intervals and export",
                            "学习波形缩放、R–R 间期和导出"
                        ),
                        symbol: "testtube.2"
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                selectedTab = .records
            } label: {
                actionRow(
                    title: language.text("Open ECG data", "打开心电数据"),
                    subtitle: language.text(
                        "Request access or browse Apple Health records",
                        "申请权限或浏览 Apple 健康记录"
                    ),
                    symbol: "waveform.path.ecg"
                )
            }
            .buttonStyle(.plain)
        }
        .watchBeatCard()
    }

    private var safetyNote: some View {
        Label(
            language.text(
                "Research use only. This app does not diagnose or provide emergency alerts.",
                "仅供研究使用。本应用不提供诊断或紧急警报。"
            ),
            systemImage: "cross.case"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .watchBeatCard()
    }

    private func metric(value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.pink)
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
    }

    private func actionRow(title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.pink)
                .frame(width: 40, height: 40)
                .background(Color.pink.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var recordCountText: String {
        guard case .loaded(let records) = viewModel.state else { return "—" }
        return "\(records.count)"
    }

    private var latestHeartRateText: String {
        guard case .loaded(let records) = viewModel.state,
              let heartRate = records.first?.averageHeartRateBPM,
              heartRate.isFinite, heartRate > 0 else { return "—" }
        return "\(heartRate.formatted(.number.precision(.fractionLength(0)))) bpm"
    }

    private var statusText: String {
        switch viewModel.state {
        case .idle, .authorizationRequired:
            return language.text(
                "Open Data to request read-only ECG access.",
                "请前往“数据”申请只读心电权限。"
            )
        case .loading:
            return language.text("Loading ECG metadata…", "正在载入心电元数据…")
        case .unavailable:
            return language.text(
                "HealthKit ECG is unavailable; the built-in example remains available.",
                "HealthKit 心电不可用；你仍可查看内置示例。"
            )
        case .noAccessibleRecords:
            return language.text(
                "No accessible ECG record was returned. You can still use the example.",
                "没有返回可访问的心电记录，你仍可使用合成示例。"
            )
        case .loaded(let records):
            return language.text(
                "\(records.count) record(s) are available locally on this iPhone.",
                "此 iPhone 本地可访问 \(records.count) 条记录。"
            )
        case .failed:
            return language.text(
                "The last HealthKit query failed. Open Data to try again.",
                "上次 HealthKit 查询失败，请前往“数据”重试。"
            )
        }
    }
}
