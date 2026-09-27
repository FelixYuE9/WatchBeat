import SwiftUI
import WatchBeatModels

public struct ECGListView: View {
    @AppStorage("hasRequestedECGReadAccess") private var hasRequestedReadAccess = false
    let viewModel: ECGListViewModel
    let exampleMeasurement: ECGMeasurement?
    @Environment(\.appLanguage) private var language

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
        .toolbar {
            if viewModel.canReload {
                ToolbarItem(placement: .primaryAction) {
                    Button(language.text("Reload", "重新载入")) {
                        Task { await viewModel.load() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView(language.text("Loading ECG metadata…", "正在载入心电元数据…"))
        case .unavailable:
            placeholder(
                title: language.text("HealthKit ECG is unavailable", "HealthKit 心电不可用"),
                message: language.text(
                    "This device or OS version does not expose ECG records through HealthKit.",
                    "此设备或系统版本未通过 HealthKit 提供心电记录。"
                )
            ) {
                exampleLink
            }
        case .authorizationRequired:
            placeholder(
                title: language.text("ECG read access has not been requested", "尚未申请心电读取权限"),
                message: language.text(
                    "Only reading saved ECG records is requested. Nothing is written to Apple Health.",
                    "应用只申请读取已保存的心电记录，不会向 Apple 健康写入任何内容。"
                )
            ) {
                VStack(spacing: 12) {
                    Button(language.text("Request ECG read access", "申请心电读取权限")) {
                        Task { await requestReadAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                    exampleLink
                }
            }
        case .noAccessibleRecords:
            placeholder(
                title: language.text("No accessible ECG records", "没有可访问的心电记录"),
                message: language.text("""
                    No ECG record was returned. This can mean no saved Apple Watch ECG exists, or that \
                    read access was not granted. HealthKit does not allow these to be distinguished, so \
                    this app never claims access was denied.
                    """, "没有返回心电记录。这可能表示尚无 Apple Watch 心电记录，也可能表示未授予读取权限。HealthKit 不允许应用区分这两种情况，因此本应用不会声称权限被拒绝。")
            ) {
                VStack(spacing: 12) {
                    Button(language.text("Request ECG read access", "再次申请读取权限")) {
                        Task { await requestReadAccess() }
                    }
                    exampleLink
                }
            }
        case .loaded(let records):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if exampleMeasurement != nil {
                        Text(language.text("Learn with an example", "通过示例学习"))
                            .font(.headline)
                        exampleLink
                            .watchBeatCard()
                    }
                    Text(language.text("Your Health records", "你的健康记录"))
                        .font(.headline)
                        .padding(.top, 4)
                    ForEach(records) { record in
                        NavigationLink(value: record) {
                            ECGRecordRow(record: record)
                                .watchBeatCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationDestination(for: ECGRecord.self) { record in
                ECGDetailView(viewModel: viewModel.makeDetailViewModel(for: record))
            }
        case .failed(let message):
            placeholder(
                title: language.text("Unable to access ECG records", "无法访问心电记录"),
                message: language.text("Error: \(message)", "错误：\(message)")
            ) {
                VStack(spacing: 12) {
                    Button(language.text("Try again", "重试")) {
                        Task { await requestReadAccess() }
                    }
                    exampleLink
                }
            }
        }
    }

    @ViewBuilder
    private var exampleLink: some View {
        if let exampleMeasurement {
            NavigationLink {
                ECGDetailView(viewModel: ECGDetailViewModel(example: exampleMeasurement))
            } label: {
                Label(
                    language.text("Explore built-in synthetic ECG", "查看内置合成心电示例"),
                    systemImage: "waveform.path.ecg"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func placeholder(
        title: String,
        message: String,
        @ViewBuilder action: () -> some View = { EmptyView() }
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.path.ecg")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            action()
        }
        .watchBeatCard()
        .padding()
    }

    @MainActor
    private func requestReadAccess() async {
        if await viewModel.requestReadAccess() {
            hasRequestedReadAccess = true
        }
    }
}

public struct ECGRecordRow: View {
    let record: ECGRecord
    @Environment(\.appLanguage) private var language

    public init(record: ECGRecord) {
        self.record = record
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.startDate, format: .dateTime.year().month().day().hour().minute())
                .font(.headline)
            Text(classificationText)
                .font(.subheadline)
            Text(language.text(
                "\(String(format: "%.1f", record.durationSeconds)) s · \(record.declaredMeasurementCount) measurements",
                "\(String(format: "%.1f", record.durationSeconds)) 秒 · \(record.declaredMeasurementCount) 个测量值"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
