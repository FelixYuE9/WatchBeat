import SwiftUI

public struct SettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var storedLanguage = AppLanguage.system.rawValue
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
                    LabeledContent(language.text("Version", "版本"), value: "0.3.0 (4)")
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
}
