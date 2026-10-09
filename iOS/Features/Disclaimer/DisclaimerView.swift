import SwiftUI

/// First-launch gate. Analysis is unreachable until this is accepted.
public struct DisclaimerView: View {
    let onAccept: () -> Void
    @Environment(\.appLanguage) private var language

    public init(onAccept: @escaping () -> Void) {
        self.onAccept = onAccept
    }

    public var body: some View {
        ZStack {
            WatchBeatBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 14) {
                        WatchBeatIconBadge(systemImage: "waveform.path.ecg", size: 64)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Research use only", "仅供研究使用"))
                                .font(.largeTitle.bold())
                            Text(language.text("Read-only ECG research app", "只读心电研究应用"))
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 16) {
                        point(
                            "applewatch",
                            title: language.text("Reads Apple Watch ECGs", "读取 Apple Watch 心电"),
                            detail: language.text(
                                "Only single-lead records that the ECG app already saved to Apple Health.",
                                "只读取 Apple Watch 心电图 App 已保存到 Apple 健康的单导联记录。"
                            )
                        )
                        Divider()
                        point(
                            "lock.shield",
                            title: language.text("Stays on this iPhone", "数据留在本机"),
                            detail: language.text(
                                "It never writes to Health and never uploads data.",
                                "不会写入健康数据，也不会上传任何数据。"
                            )
                        )
                        Divider()
                        point(
                            "stethoscope",
                            title: language.text("Not a diagnosis", "不提供诊断"),
                            detail: language.text(
                                "Flags are research marks for a second look, not medical findings.",
                                "标记仅提示值得再看一眼，不是医疗结论。"
                            )
                        )
                    }
                    .watchBeatPanel()

                    VStack(alignment: .leading, spacing: 8) {
                        Label(language.text("Please read", "请注意"), systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.watchBeatAttentionText)
                        Text(language.text(MedicalDisclaimer.english, MedicalDisclaimer.chinese))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.watchBeatAttention.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                onAccept()
            } label: {
                Text(language.text("I understand — continue", "我已了解，继续"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.pink)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.bar)
        }
    }

    private func point(_ symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            WatchBeatIconBadge(systemImage: symbol, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
