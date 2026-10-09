import SwiftUI
import WatchBeatModels

public struct SettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var storedLanguage = AppLanguage.system.rawValue
    @AppStorage(ECGWaveformDebugSettings.showsModelRPeakLinesKey) private var showsModelRPeakLines = false
    @AppStorage(ECGWaveformDebugSettings.showsCandidateLinesKey) private var showsCandidateLines = false
    @Environment(\.appLanguage) private var language
    @Environment(ECGAnnotationStore.self) private var annotations
    @State private var confirmsAnnotationClear = false
    @State private var showsAnnotationClearError = false
    @State private var screeningCacheClearResult: Bool?
    let listViewModel: ECGListViewModel

    public init(listViewModel: ECGListViewModel) {
        self.listViewModel = listViewModel
    }

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
                    settingsRow(
                        language.text("ECG processing stays on this device", "心电处理仅在本机完成"),
                        systemImage: "iphone",
                        tint: .blue
                    )
                    settingsRow(
                        language.text("No analytics or health-data upload", "不含分析追踪或健康数据上传"),
                        systemImage: "lock.shield.fill",
                        tint: .green
                    )
                }

                Section {
                    Button(role: .destructive) {
                        confirmsAnnotationClear = true
                    } label: {
                        Label(language.text("Clear all local annotations", "清除所有本地批注"), systemImage: "trash")
                    }
                    .disabled(annotations.annotations.isEmpty && annotations.exampleAnnotation.isEmpty && !annotations.hasLoadFailure)
                } header: {
                    Text(language.text("Feelings and notes", "感受与批注"))
                } footer: {
                    Text(language.text("Saved feelings, tags and notes stay on this iPhone and are excluded from backup.", "已保存的感受、标签与批注仅保存在此 iPhone，并排除备份。"))
                }

                Section {
                    Button(role: .destructive) {
                        Task { @MainActor in
                            screeningCacheClearResult = await listViewModel.clearScreeningCache()
                        }
                    } label: {
                        HStack {
                            Label(language.text("Clear saved screening results", "清除已保存的筛查结果"), systemImage: "trash")
                            Spacer(minLength: 8)
                            if screeningCacheClearResult == true {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityLabel(language.text("Cleared", "已清除"))
                            } else if screeningCacheClearResult == false {
                                Text(language.text("Unlock and retry", "请解锁后重试"))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } header: {
                    Text(language.text("Screening results", "筛查结果"))
                } footer: {
                    Text(language.text(
                        "Each ECG's screening result (candidate count only, no waveform, date or report) is kept on this iPhone so reopening WatchBeat only analyzes new recordings. Excluded from backup and recalculated automatically when the algorithm changes or after clearing.",
                        "每条 ECG 的筛查结果（仅候选数，不含波形、日期或报告）保存在此 iPhone，重新打开时只分析新增记录。不参与备份；算法更新或清除后会自动重新计算。"
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

                Section {
                    LabeledContent(language.text("Version", "版本"), value: appVersion)
                } header: {
                    Text(language.text("About", "关于"))
                } footer: {
                    Text(language.text(
                        "Research use only — not a medical diagnosis.",
                        "仅供研究使用，不构成医疗诊断。"
                    ))
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(language.text("Settings", "设置"))
        .confirmationDialog(language.text("Clear all local annotations?", "清除所有本地批注？"), isPresented: $confirmsAnnotationClear) {
            Button(language.text("Clear annotations", "清除批注"), role: .destructive) {
                if !annotations.clear() { showsAnnotationClearError = true }
            }
            Button(language.text("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(language.text("This removes saved feelings, tags and notes from WatchBeat. Apple Health ECGs are unaffected.", "此操作会删除 WatchBeat 保存的感受、标签和文字批注，不影响 Apple 健康中的 ECG。"))
        }
        .alert(language.text("Annotations could not be cleared", "无法清除批注"), isPresented: $showsAnnotationClearError) {
            Button(language.text("OK", "好"), role: .cancel) {}
        } message: {
            Text(language.text("Unlock the device and try again.", "请解锁设备后重试。"))
        }
    }

    private func settingsRow(_ title: String, systemImage: String, tint: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
