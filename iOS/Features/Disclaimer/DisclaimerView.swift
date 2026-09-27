import SwiftUI

/// First-launch gate. Analysis is unreachable until this is accepted.
public struct DisclaimerView: View {
    let onAccept: () -> Void
    @Environment(\.appLanguage) private var language

    public init(onAccept: @escaping () -> Void) {
        self.onAccept = onAccept
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(language.text("Research use only", "仅供研究使用"))
                    .font(.title)
                    .bold()

                Text(language.text("Read-only ECG research app", "只读心电研究应用"))
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(language.text(MedicalDisclaimer.english, MedicalDisclaimer.chinese))

                Text(language.text(
                    """
                    The app reads single-lead ECG records that the Apple Watch ECG app already saved to \
                    Apple Health. It never writes to Health, never uploads data, and does not diagnose.
                    """,
                    "本应用只读取 Apple Watch 心电图 App 已保存到 Apple 健康的单导联心电记录。它不会写入健康数据、不会上传数据，也不提供诊断。"
                ))
                    .foregroundStyle(.secondary)

                Button {
                    onAccept()
                } label: {
                    Text(language.text("I understand — continue", "我已了解，继续"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
