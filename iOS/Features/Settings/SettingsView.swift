import SwiftUI

public struct SettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var storedLanguage = AppLanguage.system.rawValue
    @AppStorage(ECGWaveformDebugSettings.showsModelRPeakLinesKey) private var showsModelRPeakLines = false
    @AppStorage(ECGWaveformDebugSettings.showsCandidateLinesKey) private var showsCandidateLines = false
    @Environment(\.appLanguage) private var language

    public init() {}

    public var body: some View {
        ZStack {
            WatchBeatBackground()
            Form {
                Section {
                    Picker(
                        language.text("App language", "应用语言"),
                        selection: $storedLanguage
                    ) {
                        Text(language.text("Follow System", "跟随系统"))
                            .tag(AppLanguage.system.rawValue)
                        Text("简体中文")
                            .tag(AppLanguage.simplifiedChinese.rawValue)
                        Text("English")
                            .tag(AppLanguage.english.rawValue)
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text(language.text("Language", "语言"))
                } footer: {
                    Text(language.text(
                        "The interface updates immediately. ECG values and exported data are unchanged.",
                        "界面会立即更新；心电数值和导出数据不会改变。"
                    ))
                }

                Section {
                    Toggle(
                        language.text("Model R-peak lines", "模型 R 峰竖线"),
                        isOn: $showsModelRPeakLines
                    )
                    Toggle(
                        language.text("Premature-candidate lines", "疑似早搏候选竖线"),
                        isOn: $showsCandidateLines
                    )
                } header: {
                    Text(language.text("Research debugging", "研究调试"))
                } footer: {
                    Text(language.text(
                        "Draws full-height model lines on the waveform for checking detector behavior. " +
                            "Not needed for everyday reading: the R–R strip and yellow shading already " +
                            "show the timing and the candidates.",
                        "在波形上绘制模型的整列竖线，用于检查检测效果。日常查看无需开启：" +
                            "波形上方的 R–R 间期和黄色底色已包含时序与候选信息。"
                    ))
                }

                Section(language.text("Privacy", "隐私")) {
                    Label(
                        language.text("ECG processing stays on this device", "心电处理仅在本机完成"),
                        systemImage: "iphone"
                    )
                    Label(
                        language.text("No analytics or health-data upload", "不含分析追踪或健康数据上传"),
                        systemImage: "lock.shield"
                    )
                }

                Section(language.text("About", "关于")) {
                    LabeledContent(language.text("Version", "版本"), value: appVersion)
                    Text(language.text(
                        "Research use only — not a medical diagnosis.",
                        "仅供研究使用，不构成医疗诊断。"
                    ))
                    .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(language.text("Settings", "设置"))
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
