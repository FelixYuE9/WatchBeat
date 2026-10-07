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
    @State private var trendMetric = TrendMetric.recordings

    private enum TrendMetric: Hashable {
        case recordings
        case heartRate
    }

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
                VStack(alignment: .leading, spacing: 14) {
                    statusCard
                    if case .loaded = viewModel.state {
                        insightsSection
                    }
                    exampleSection
                    WatchBeatFootnote(
                        text: language.text(
                            "Research use only. This app does not diagnose or provide emergency alerts.",
                            "仅供研究使用。本应用不提供诊断或紧急警报。"
                        ),
                        systemImage: "cross.case"
                    )
                    .padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(language.text("Overview", "概览"))
        .onAppear { viewModel.startScreeningIfNeeded() }
    }

    // MARK: - Status

    /// One card answering "where do I stand": record access, the latest recording and, before
    /// access is granted, the way to get it.
    private var statusCard: some View {
        HStack(alignment: .top, spacing: 14) {
            WatchBeatIconBadge(systemImage: statusSymbol, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle)
                    .font(.headline)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .loaded = viewModel.state {
                    EmptyView()
                } else if case .loading = viewModel.state {
                    ProgressView()
                        .padding(.top, 4)
                } else {
                    Button {
                        selectedTab = .records
                    } label: {
                        Label(language.text("Open ECG data", "打开心电数据"), systemImage: "arrow.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .watchBeatPanel()
    }

    private var statusSymbol: String {
        switch viewModel.state {
        case .loaded: return "heart.text.square.fill"
        case .idle, .authorizationRequired: return "lock.shield"
        case .loading: return "arrow.triangle.2.circlepath"
        case .unavailable: return "heart.slash"
        case .noAccessibleRecords: return "waveform.path.ecg"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var statusTitle: String {
        switch viewModel.state {
        case .loaded(let records):
            return language.text(
                "\(records.count) ECG record(s) on this iPhone",
                "此 iPhone 可访问 \(records.count) 条 ECG"
            )
        case .idle, .authorizationRequired:
            return language.text("Connect Apple Health", "连接 Apple 健康")
        case .loading:
            return language.text("Loading ECG metadata…", "正在载入心电元数据…")
        case .unavailable:
            return language.text("HealthKit ECG unavailable", "HealthKit 心电不可用")
        case .noAccessibleRecords:
            return language.text("No accessible ECG yet", "暂无可访问的 ECG")
        case .failed:
            return language.text("Health query failed", "健康数据查询失败")
        }
    }

    private var statusText: String {
        switch viewModel.state {
        case .idle, .authorizationRequired:
            return language.text(
                "Open Data to request read-only ECG access. Analysis stays on this device.",
                "前往“数据”申请只读心电权限，分析仅在本机完成。"
            )
        case .loading:
            return language.text(
                "Records appear here once HealthKit responds.",
                "HealthKit 返回后，记录会显示在这里。"
            )
        case .unavailable:
            return language.text(
                "The built-in example below remains available.",
                "你仍可查看下方的内置示例。"
            )
        case .noAccessibleRecords:
            return language.text(
                "No ECG record was returned. You can still use the example below.",
                "没有返回心电记录，你仍可使用下方的合成示例。"
            )
        case .loaded(let records):
            guard let latest = records.max(by: { $0.startDate < $1.startDate }) else {
                return language.text("Analysis stays on this device.", "分析仅在本机完成。")
            }
            let date = latest.startDate.formatted(
                .dateTime.month().day().hour().minute().locale(language.locale)
            )
            if let bpm = latest.averageHeartRateBPM, bpm.isFinite, bpm > 0 {
                return language.text(
                    "Latest: \(date) · \(Int(bpm.rounded())) BPM",
                    "最近一次：\(date) · \(Int(bpm.rounded())) BPM"
                )
            }
            return language.text("Latest: \(date)", "最近一次：\(date)")
        case .failed:
            return language.text(
                "The last HealthKit query failed. Open Data to try again.",
                "上次 HealthKit 查询失败，请前往“数据”重试。"
            )
        }
    }

    // MARK: - Insights

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
        return VStack(alignment: .leading, spacing: 14) {
            WatchBeatGroupHeader(language.text("Recording insights", "记录分析")) {
                Button {
                    viewModel.filter = period
                    selectedTab = .records
                } label: {
                    HStack(spacing: 3) {
                        Text(language.text("Browse", "查看记录"))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                }
                .accessibilityLabel(language.text("Browse this date range", "查看此日期范围的记录"))
            }
            .padding(.top, 10)

            ECGDateRangePicker(filter: $period)

            if summary.recordCount == 0 {
                ECGEmptyStateCard(
                    symbol: "calendar",
                    title: language.text("No recordings in this range", "此范围内没有记录"),
                    message: language.text(
                        "No accessible ECGs in this date range. Try a wider range.",
                        "此日期范围内没有可访问的 ECG，可尝试扩大范围。"
                    )
                )
            } else {
                summaryGrid(summary)
                coverageCard(summary)
                trendsCard(summary)
                tagCard(summary)
            }
        }
    }

    private func summaryGrid(_ summary: ECGRecordInsights) -> some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            summaryTile(
                value: "\(summary.recordCount)",
                label: language.text("Recordings", "记录"),
                symbol: "waveform.path.ecg",
                tint: .pink
            )
            summaryTile(
                value: summary.averageHeartRateBPM.map { "\(Int($0.rounded()))" } ?? "—",
                unit: summary.averageHeartRateBPM == nil ? nil : "BPM",
                label: language.text("Mean recorded HR", "记录平均心率"),
                symbol: "heart.fill",
                tint: .pink
            )
            summaryTile(
                value: summary.analyzedCount > 0 ? "\(summary.candidateCount)" : "—",
                label: language.text("Candidates flagged", "标记候选"),
                symbol: "flag.fill",
                tint: summary.candidateCount > 0 ? Color.watchBeatAttentionText : Color.secondary,
                isHighlighted: summary.candidateCount > 0
            )
            summaryTile(
                value: annotations.hasLoadFailure ? "—" : "\(summary.annotatedCount)",
                label: language.text("Annotated", "有批注"),
                symbol: "text.bubble.fill",
                tint: .secondary
            )
        }
    }

    private func summaryTile(
        value: String,
        unit: String? = nil,
        label: String,
        symbol: String,
        tint: Color,
        isHighlighted: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(isHighlighted ? Color.watchBeatAttentionText : Color.primary)
                if let unit {
                    Text(unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isHighlighted ? Color.watchBeatAttention.opacity(0.14) : Color.watchBeatSurface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Coverage

    private struct CoverageSegment: Identifiable {
        let id: String
        let title: String
        let count: Int
        let color: Color
    }

    private func coverageSegments(_ summary: ECGRecordInsights) -> [CoverageSegment] {
        [
            CoverageSegment(
                id: "candidates", title: language.text("With candidates", "有疑似候选"),
                count: summary.candidateRecordCount, color: .watchBeatAttention
            ),
            CoverageSegment(
                id: "clear", title: language.text("No candidates flagged", "未标记候选"),
                count: summary.analyzedCount - summary.candidateRecordCount, color: Color.secondary.opacity(0.55)
            ),
            CoverageSegment(
                id: "unable", title: language.text("Unable to analyze", "无法分析"),
                count: summary.unableToAnalyzeCount, color: Color.secondary.opacity(0.25)
            ),
            CoverageSegment(
                id: "failed", title: language.text("Read failed", "读取失败"),
                count: summary.failedCount, color: .orange
            ),
            CoverageSegment(
                id: "pending", title: language.text("Pending analysis", "待分析"),
                count: summary.pendingCount, color: Color.watchBeatInset
            )
        ]
    }

    private func coverageCard(_ summary: ECGRecordInsights) -> some View {
        let segments = coverageSegments(summary)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                WatchBeatSectionTitle(language.text("Analysis coverage", "分析覆盖"), systemImage: "checkmark.circle")
                Spacer(minLength: 8)
                Text("\(summary.analyzedCount) / \(summary.recordCount)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let total = max(summary.recordCount, 1)
                let visible = segments.filter { $0.count > 0 }
                let gaps = CGFloat(max(visible.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    ForEach(visible) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: max(0, proxy.size.width - gaps) * CGFloat(segment.count) / CGFloat(total))
                    }
                }
                .frame(width: proxy.size.width, alignment: .leading)
                .background(Color.watchBeatInset)
                .clipShape(Capsule())
            }
            .frame(height: 12)
            .accessibilityElement()
            .accessibilityLabel(language.text(
                "Analyzed \(summary.analyzedCount) of \(summary.recordCount) recordings",
                "已分析 \(summary.analyzedCount) / \(summary.recordCount) 条记录"
            ))

            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(segments) { segment in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(segment.color)
                            .overlay { Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5) }
                            .frame(width: 9, height: 9)
                        Text(segment.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        Text("\(segment.count)")
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    .font(.caption)
                    .foregroundStyle(segment.count == 0 ? Color.secondary : Color.primary)
                    .padding(.trailing, 6)
                }
            }

            Text(language.text(
                "Counts update as on-device screening finishes. These sampled ECGs do not estimate whole-day premature-beat burden.",
                "统计会随本机筛查完成而更新。短时 ECG 抽样不能用于估算全天早搏负荷。"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .watchBeatPanel()
    }

    // MARK: Trends

    private func trendsCard(_ summary: ECGRecordInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WatchBeatSectionTitle(language.text("Trends", "趋势"), systemImage: "chart.bar.xaxis")

            Picker(language.text("Trend", "趋势"), selection: $trendMetric) {
                Text(language.text(groupsByMonth ? "Per month" : "Per day", groupsByMonth ? "每月记录数" : "每日记录数"))
                    .tag(TrendMetric.recordings)
                Text(language.text("Heart rate", "平均心率"))
                    .tag(TrendMetric.heartRate)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch trendMetric {
            case .recordings:
                recordingsChart(summary)
            case .heartRate:
                heartRateChart(summary)
            }

            Text(language.text(
                "Only recorded ECGs are summarized; gaps in recording are not continuous monitoring.",
                "仅汇总实际记录的 ECG；记录间的空白不代表持续监测。"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .watchBeatPanel()
    }

    private func recordingsChart(_ summary: ECGRecordInsights) -> some View {
        let flagged = language.text("With candidates", "有疑似候选")
        let other = language.text("Other recordings", "其他记录")
        let unit: Calendar.Component = groupsByMonth ? .month : .day
        return Chart {
            ForEach(summary.buckets) { bucket in
                BarMark(
                    x: .value(language.text("Date", "日期"), bucket.date, unit: unit),
                    y: .value(language.text("Recordings", "记录数"), bucket.recordCount - bucket.candidateRecordCount)
                )
                .foregroundStyle(by: .value(language.text("Result", "结果"), other))
                BarMark(
                    x: .value(language.text("Date", "日期"), bucket.date, unit: unit),
                    y: .value(language.text("Recordings", "记录数"), bucket.candidateRecordCount)
                )
                .foregroundStyle(by: .value(language.text("Result", "结果"), flagged))
            }
        }
        .chartForegroundStyleScale(
            domain: [other, flagged],
            range: [Color.pink.opacity(0.55), Color.watchBeatAttention]
        )
        .chartLegend(position: .bottom, alignment: .leading)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
        .frame(height: 170)
    }

    @ViewBuilder
    private func heartRateChart(_ summary: ECGRecordInsights) -> some View {
        if summary.heartRateRecordCount > 0 {
            Chart(summary.buckets) { bucket in
                if let heartRate = bucket.averageHeartRateBPM {
                    LineMark(
                        x: .value(language.text("Date", "日期"), bucket.date),
                        y: .value("BPM", heartRate)
                    )
                    .foregroundStyle(Color.pink)
                    PointMark(
                        x: .value(language.text("Date", "日期"), bucket.date),
                        y: .value("BPM", heartRate)
                    )
                    .foregroundStyle(Color.pink)
                    .symbolSize(28)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            .frame(height: 170)
            Text(language.text(
                "Mean of \(summary.heartRateRecordCount) ECG record(s) with a valid Apple average heart rate.",
                "均值来自 \(summary.heartRateRecordCount) 条具有有效 Apple 平均心率的 ECG 记录。"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            Text(language.text(
                "These records have no valid Apple average heart rate to plot.",
                "这些记录没有可绘制的有效 Apple 平均心率。"
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    // MARK: Tags

    private func tagCard(_ summary: ECGRecordInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WatchBeatSectionTitle(language.text("Feelings and tags", "感受与标签"), systemImage: "tag")

            if annotations.hasLoadFailure {
                HStack {
                    Text(language.text(
                        "Saved annotations could not be read.",
                        "无法读取已保存的批注。"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    Spacer(minLength: 8)
                    Button(language.text("Retry", "重试")) { annotations.reload() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else if summary.tagCounts.isEmpty {
                Text(language.text(
                    "Add feelings or custom tags in an ECG detail to see their frequency here.",
                    "在 ECG 详情中添加感受或自定义标签后，即可在这里查看出现次数。"
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(summary.tagCounts) { entry in
                        tagRow(entry, total: summary.recordCount)
                    }
                }
            }

            Text(language.text(
                "Self-reported tags can overlap. Counts describe your notes and do not establish symptom causes.",
                "自述标签可重叠；次数只描述你的记录，不推断症状原因。"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .watchBeatPanel()
    }

    private func tagRow(_ entry: ECGTagCount, total: Int) -> some View {
        Button {
            viewModel.filter = period
            viewModel.filter.tags = [entry.tag]
            selectedTab = .records
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(entry.tag.title(in: language))
                        .font(.subheadline)
                    Spacer(minLength: 8)
                    Text(language.text("\(entry.count) recordings", "\(entry.count) 条"))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.watchBeatInset)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Color.pink.opacity(0.7))
                                .frame(width: proxy.size.width * CGFloat(entry.count) / CGFloat(max(total, 1)))
                        }
                }
                .frame(height: 6)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(language.text("Show matching recordings", "查看匹配记录"))
    }

    // MARK: - Example

    @ViewBuilder
    private var exampleSection: some View {
        if let exampleMeasurement {
            WatchBeatGroupHeader(language.text("Learn with an example", "从示例开始"))
                .padding(.top, 10)
            NavigationLink {
                ECGDetailView(viewModel: ECGDetailViewModel(example: exampleMeasurement))
            } label: {
                HStack(spacing: 12) {
                    WatchBeatIconBadge(systemImage: "testtube.2", tint: .orange, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text("Explore the ECG example", "查看合成心电示例"))
                            .font(.headline)
                        Text(language.text(
                            "Learn waveform zoom, R–R intervals, measuring and export",
                            "了解波形缩放、R–R 间期、测量与导出"
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .watchBeatPanel()
            }
            .buttonStyle(.plain)
        }
    }
}
