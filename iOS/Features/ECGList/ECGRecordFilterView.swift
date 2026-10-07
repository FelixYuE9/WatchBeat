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
            if filter.dateRange == .custom {
                DatePicker(language.text("From", "开始日期"), selection: $filter.startDate, displayedComponents: .date)
                DatePicker(language.text("Through", "结束日期"), selection: $filter.endDate, displayedComponents: .date)
                if Calendar.current.startOfDay(for: filter.startDate) > Calendar.current.startOfDay(for: filter.endDate) {
                    Text(language.text("The end date must be on or after the start date.", "结束日期不能早于开始日期。"))
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
}

struct ECGRecordFilterView: View {
    @Binding var filter: ECGRecordFilter
    let availableTags: [ECGRecordTag]
    @State private var showsMoreFilters = false
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(language.text("Find recordings", "查找记录"), systemImage: "line.3.horizontal.decrease.circle")
                    .font(.headline)
                Spacer()
                Button(language.text("Reset", "重置")) { filter = ECGRecordFilter() }
                    .font(.subheadline)
            }
            ECGDateRangePicker(filter: $filter)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(language.text("Search notes or tags", "搜索批注或标签"), text: $filter.query)
                    .textFieldStyle(.plain)
                if !filter.query.isEmpty {
                    Button { filter.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel(language.text("Clear search", "清空搜索"))
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            DisclosureGroup(
                language.text("Result and tags (\(filter.tags.count) selected)", "结果与标签（已选 \(filter.tags.count) 个）"),
                isExpanded: $showsMoreFilters
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(language.text("Analysis result", "分析结果"), selection: $filter.result) {
                        ForEach(ECGResultFilter.allCases) { result in
                            Text(resultTitle(result)).tag(result)
                        }
                    }
                    if availableTags.isEmpty {
                        Text(language.text("Add feelings or tags in an ECG detail to filter by them here.", "在 ECG 详情中添加感受或标签后，可在这里按标签筛选。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    // Keep selected tags visible even if their last assignment was removed.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], alignment: .leading, spacing: 8) {
                        ForEach(displayedTags) { tag in
                            ECGSelectableTag(title: tag.title(in: language), selected: filter.tags.contains(tag)) {
                                if filter.tags.contains(tag) { filter.tags.remove(tag) }
                                else { filter.tags.insert(tag) }
                            }
                        }
                    }
                    Text(language.text("Matches any selected tag, together with dates, result and search text.", "多个标签匹配任意一个；日期、结果和搜索文字需同时满足。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 10)
            }
        }
        .watchBeatCard()
        .onAppear { if !filter.tags.isEmpty || filter.result != .all { showsMoreFilters = true } }
        .onChange(of: filter.tags) { _, tags in if !tags.isEmpty { showsMoreFilters = true } }
    }

    private var displayedTags: [ECGRecordTag] {
        let extra = filter.tags.filter { !availableTags.contains($0) }.sorted { $0.id < $1.id }
        return availableTags + extra
    }

    private func resultTitle(_ result: ECGResultFilter) -> String {
        switch result {
        case .all: return language.text("All results", "全部结果")
        case .candidates: return language.text("With candidates", "有疑似候选")
        case .noCandidates: return language.text("No candidates flagged", "未标记候选")
        case .unableToAnalyze: return language.text("Unable to analyze", "无法分析")
        case .pending: return language.text("Pending analysis", "待分析")
        case .failed: return language.text("Read failed", "读取失败")
        }
    }
}

struct ECGSelectableTag: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                Text(title).multilineTextAlignment(.leading)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .padding(8)
            .background(selected ? Color.pink.opacity(0.15) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.pink : Color.primary)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
