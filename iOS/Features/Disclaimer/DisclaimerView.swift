import SwiftUI

/// First-launch gate. Analysis is unreachable until this is accepted.
public struct DisclaimerView: View {
    let onAccept: () -> Void

    public init(onAccept: @escaping () -> Void) {
        self.onAccept = onAccept
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Research use only")
                    .font(.title)
                    .bold()

                Text("Read-only ECG research app")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(MedicalDisclaimer.english)
                Text(MedicalDisclaimer.chinese)

                Text("""
                    The app reads single-lead ECG records that the Apple Watch ECG app already saved to \
                    Apple Health. It never writes to Health, never uploads data, and does not diagnose.
                    """)
                    .foregroundStyle(.secondary)

                Button {
                    onAccept()
                } label: {
                    Text("I understand — continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
