import SwiftUI
import WatchBeatModels

extension ECGRecordTag {
    func title(in language: AppLanguage) -> String {
        switch self {
        case .custom(let name): return name
        case .feeling(let feeling):
            switch feeling {
            case .noSymptoms: return language.text("No discomfort", "没有不适")
            case .palpitations: return language.text("Palpitations", "心悸")
            case .skippedBeats: return language.text("Skipped heartbeat", "漏跳感")
            case .chestDiscomfort: return language.text("Chest discomfort", "胸部不适")
            case .breathlessness: return language.text("Shortness of breath", "气短")
            case .dizziness: return language.text("Dizziness", "头晕")
            case .fatigue: return language.text("Fatigue", "疲劳")
            case .anxiety: return language.text("Anxiety", "焦虑")
            }
        }
    }
}

extension ECGDateRange {
    func title(in language: AppLanguage) -> String {
        switch self {
        case .all: return language.text("All", "全部")
        case .last7Days: return language.text("7 days", "近 7 天")
        case .last30Days: return language.text("30 days", "近 30 天")
        case .custom: return language.text("Custom", "自定义")
        }
    }
}

extension ECGResultFilter {
    func title(in language: AppLanguage) -> String {
        switch self {
        case .all: return language.text("All results", "全部结果")
        case .candidates: return language.text("With candidates", "有疑似候选")
        case .noCandidates: return language.text("No candidates flagged", "未标记候选")
        case .unableToAnalyze: return language.text("Unable to analyze", "无法分析")
        case .pending: return language.text("Pending analysis", "待分析")
        case .failed: return language.text("Read failed", "读取失败")
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.stack"
        case .candidates: return "flag.fill"
        case .noCandidates: return "checkmark.circle"
        case .unableToAnalyze: return "questionmark.circle"
        case .pending: return "hourglass"
        case .failed: return "exclamationmark.circle"
        }
    }
}

/// Segmented date range, plus a compact from/through row for a custom range.
struct ECGDateRangePicker: View {
    @Binding var filter: ECGRecordFilter
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(language.text("Recording dates", "记录日期"), selection: $filter.dateRange) {
                ForEach(ECGDateRange.allCases) { range in
                    Text(range.title(in: language)).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if filter.dateRange == .custom {
                VStack(spacing: 0) {
                    DatePicker(language.text("From", "开始日期"), selection: $filter.startDate, displayedComponents: .date)
                        .padding(.vertical, 6)
                    Divider()
                    DatePicker(language.text("Through", "结束日期"), selection: $filter.endDate, displayedComponents: .date)
                        .padding(.vertical, 6)
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .background(Color.watchBeatSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if Calendar.current.startOfDay(for: filter.startDate) > Calendar.current.startOfDay(for: filter.endDate) {
                    Label(
                        language.text("The end date must be on or after the start date.", "结束日期不能早于开始日期。"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
    }
}

/// Search, date range and the active result/tag filters, laid directly on the page above the list.
/// Result and tag choices live in `ECGRecordFilterSheet` so the list starts high on the screen.
struct ECGRecordFilterBar: View {
    @Binding var filter: ECGRecordFilter
    let availableTags: [ECGRecordTag]
    @State private var showsFilterSheet = false
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                searchField
                Button {
                    showsFilterSheet = true
                } label: {
                    Image(systemName: hasRefinements
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle")
                        .font(.title3)
                        .frame(width: 42, height: 42)
                        .background(Color.watchBeatSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(hasRefinements ? Color.pink : Color.primary)
                .accessibilityLabel(language.text("Result and tag filters", "结果与标签筛选"))
                .accessibilityValue(language.text("\(refinementCount) active", "已启用 \(refinementCount) 项"))
            }

            ECGDateRangePicker(filter: $filter)

            if hasRefinements {
                activeFilters
            }
        }
        .sheet(isPresented: $showsFilterSheet) {
            ECGRecordFilterSheet(filter: $filter, availableTags: availableTags)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(language.text("Search notes or tags", "搜索批注或标签"), text: $filter.query)
                .textFieldStyle(.plain)
                .submitLabel(.search)
            if !filter.query.isEmpty {
                Button {
                    filter.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.text("Clear search", "清空搜索"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color.watchBeatSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Removable chips for the result and tag filters chosen in the sheet.
    private var activeFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if filter.result != .all {
                    removableChip(filter.result.title(in: language), systemImage: filter.result.systemImage) {
                        filter.result = .all
                    }
                }
                ForEach(filter.tags.sorted { $0.id < $1.id }) { tag in
                    removableChip(tag.title(in: language), systemImage: "tag") {
                        filter.tags.remove(tag)
                    }
                }
                Button(language.text("Clear", "清除")) {
                    filter.result = .all
                    filter.tags = []
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 6)
            }
        }
    }

    private func removableChip(_ title: String, systemImage: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                Text(title)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.pink.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.text("Remove filter \(title)", "移除筛选：\(title)"))
    }

    private var refinementCount: Int {
        filter.tags.count + (filter.result == .all ? 0 : 1)
    }

    private var hasRefinements: Bool { refinementCount > 0 }
}

/// Analysis result and tag filters, presented as a sheet from the data page.
struct ECGRecordFilterSheet: View {
    @Binding var filter: ECGRecordFilter
    let availableTags: [ECGRecordTag]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(language.text("Analysis result", "分析结果"), selection: $filter.result) {
                        ForEach(ECGResultFilter.allCases) { result in
                            Label(result.title(in: language), systemImage: result.systemImage)
                                .tag(result)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(language.text("Analysis result", "分析结果"))
                } footer: {
                    Text(language.text(
                        "Result matches update as on-device screening finishes.",
                        "分析结果筛选会随本机筛查完成而更新。"
                    ))
                }

                Section {
                    if displayedTags.isEmpty {
                        Text(language.text(
                            "Add feelings or tags in an ECG detail to filter by them here.",
                            "在 ECG 详情中添加感受或标签后，可在这里按标签筛选。"
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    } else {
                        WatchBeatFlowLayout(spacing: 8, lineSpacing: 8) {
                            // Keep selected tags visible even if their last assignment was removed.
                            ForEach(displayedTags) { tag in
                                ECGSelectableTag(
                                    title: tag.title(in: language),
                                    selected: filter.tags.contains(tag)
                                ) {
                                    if filter.tags.contains(tag) {
                                        filter.tags.remove(tag)
                                    } else {
                                        filter.tags.insert(tag)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text(language.text("Feelings and tags", "感受与标签"))
                } footer: {
                    Text(language.text(
                        "Matches any selected tag, together with dates, result and search text.",
                        "多个标签匹配任意一个；日期、结果和搜索文字需同时满足。"
                    ))
                }
            }
            .navigationTitle(language.text("Filters", "筛选"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("Reset", "重置")) {
                        filter.result = .all
                        filter.tags = []
                    }
                    .disabled(filter.result == .all && filter.tags.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("Done", "完成")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var displayedTags: [ECGRecordTag] {
        let extra = filter.tags.filter { !availableTags.contains($0) }.sorted { $0.id < $1.id }
        return availableTags + extra
    }
}

/// Toggleable capsule used by the tag filter and the annotation editor.
struct ECGSelectableTag: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .multilineTextAlignment(.leading)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.pink : Color.watchBeatInset, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
