import SwiftUI
import WatchBeatModels

public struct OverviewView: View {
    let viewModel: ECGListViewModel
    let exampleMeasurement: ECGMeasurement?
    @Binding var selectedTab: AppTab
    @Environment(\.appLanguage) private var language

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
                    quickActions
                    safetyNote
                }
                .padding()
            }
        }
        .navigationTitle(language.text("Overview", "概览"))
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
              let heartRate = records.first?.averageHeartRateBPM else { return "—" }
        return "\(Int(heartRate.rounded())) bpm"
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
