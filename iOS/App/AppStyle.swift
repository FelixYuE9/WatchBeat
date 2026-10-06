import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public extension Color {
    /// Tint for research flags. Deliberately yellow, never red: WatchBeat does not diagnose, so a
    /// flag should read as "worth a second look", not as a clinical alarm.
    static let watchBeatAttention = Color(red: 1.0, green: 0.8, blue: 0.0)

    /// Text and icon tone of the same hue that stays readable on light and dark cards.
    static var watchBeatAttentionText: Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 1.0, green: 0.84, blue: 0.32, alpha: 1)
                : UIColor(red: 0.55, green: 0.38, blue: 0.0, alpha: 1)
        })
        #else
        Color(red: 0.7, green: 0.5, blue: 0.0)
        #endif
    }
}

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

/// Opaque card surface shared by the ECG data list and the detail page, so both read as one app.
private struct WatchBeatSurfaceModifier: ViewModifier {
    /// Left accent stripe; `nil` draws none.
    let stripe: Color?
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
                if let stripe {
                    Capsule()
                        .fill(stripe)
                        .frame(width: 4)
                        .padding(.leading, 6)
                        .padding(.vertical, 15)
                }
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 8, y: 3)
    }

    private var cardColor: Color {
        colorScheme == .dark
            ? Color(red: 0.105, green: 0.105, blue: 0.13)
            : Color(red: 0.995, green: 0.995, blue: 1)
    }

    private var borderColor: Color {
        isFlagged
            ? Color.watchBeatAttention.opacity(colorScheme == .dark ? 0.75 : 0.95)
            : Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.1)
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

    /// Tappable rows on the ECG data page. Unflagged rows get a quiet grey stripe so that only a
    /// research flag draws the eye.
    func watchBeatDataCard(isFlagged: Bool = false) -> some View {
        modifier(WatchBeatSurfaceModifier(
            stripe: isFlagged ? Color.watchBeatAttention : Color.secondary.opacity(0.28),
            isFlagged: isFlagged
        ))
    }

    /// Section cards on the ECG detail page: the data-card surface without a stripe.
    func watchBeatPanel() -> some View {
        modifier(WatchBeatSurfaceModifier(stripe: nil, isFlagged: false))
    }
}

/// Large value with a short caption, used for key numbers on the detail page. Highlighting uses the
/// research-flag yellow; everything else stays neutral.
struct WatchBeatMetricTile: View {
    let value: String
    let label: String
    var isHighlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(isHighlighted ? Color.watchBeatAttentionText : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Fills the row height so tiles in an HStack with `.fixedSize(vertical:)` line up.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            isHighlighted ? Color.watchBeatAttention.opacity(0.16) : Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Card title with a muted icon, shared by the detail page sections.
struct WatchBeatSectionTitle: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title)
                .font(.headline)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
    }
}
