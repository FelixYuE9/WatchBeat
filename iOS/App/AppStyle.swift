import SwiftUI

public struct WatchBeatBackground: View {
    public init() {}

    public var body: some View {
        LinearGradient(
            colors: [
                Color.pink.opacity(0.16),
                Color.purple.opacity(0.08),
                Color.blue.opacity(0.08),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct WatchBeatDataCardModifier: ViewModifier {
    let isFlagged: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(borderColor, lineWidth: isFlagged ? 1.5 : 1)
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(isFlagged ? Color.red : Color.pink)
                    .frame(width: 4)
                    .padding(.leading, 6)
                    .padding(.vertical, 15)
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.12), radius: 8, y: 3)
    }

    private var cardColor: Color {
        colorScheme == .dark
            ? Color(red: 0.105, green: 0.105, blue: 0.13)
            : Color(red: 0.995, green: 0.995, blue: 1)
    }

    private var borderColor: Color {
        isFlagged
            ? Color.red.opacity(colorScheme == .dark ? 0.8 : 0.62)
            : Color.primary.opacity(colorScheme == .dark ? 0.34 : 0.16)
    }
}

public extension View {
    func watchBeatCard() -> some View {
        padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.42), lineWidth: 0.7)
            }
    }

    /// Higher-contrast treatment for tappable rows on the ECG data page.
    func watchBeatDataCard(isFlagged: Bool = false) -> some View {
        modifier(WatchBeatDataCardModifier(isFlagged: isFlagged))
    }
}
