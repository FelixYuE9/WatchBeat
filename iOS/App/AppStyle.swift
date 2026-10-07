import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
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

    /// Page background behind every card (the system grouped background).
    static var watchBeatCanvas: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.clear
        #endif
    }

    /// Opaque card surface that sits on `watchBeatCanvas`.
    static var watchBeatSurface: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.primary.opacity(0.04)
        #endif
    }

    /// Quiet fill for tiles, chips and fields inside a card.
    static let watchBeatInset = Color.primary.opacity(0.055)
}

/// Grouped canvas with a faint brand wash at the top; shared by every tab.
public struct WatchBeatBackground: View {
    public init() {}

    public var body: some View {
        Color.watchBeatCanvas
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Color.pink.opacity(0.09), Color.pink.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 280)
            }
            .ignoresSafeArea()
    }
}

/// The one card surface of the app: overview, data list, detail page and filters all use it.
private struct WatchBeatSurfaceModifier: ViewModifier {
    /// Left accent stripe; `nil` draws none.
    let stripe: Color?
    let isFlagged: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .padding(.leading, stripe == nil ? 0 : 4)
            .background(Color.watchBeatSurface, in: shape)
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: isFlagged ? 1.5 : 0.5)
            }
            .overlay(alignment: .leading) {
                if let stripe {
                    Capsule()
                        .fill(stripe)
                        .frame(width: 4)
                        .padding(.leading, 7)
                        .padding(.vertical, 16)
                }
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.035), radius: 6, y: 2)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    private var borderColor: Color {
        isFlagged
            ? Color.watchBeatAttention.opacity(colorScheme == .dark ? 0.7 : 0.9)
            : Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.06)
    }
}

public extension View {
    /// Tappable rows on the ECG data page. Unflagged rows get a quiet grey stripe so that only a
    /// research flag draws the eye.
    func watchBeatDataCard(isFlagged: Bool = false) -> some View {
        modifier(WatchBeatSurfaceModifier(
            stripe: isFlagged ? Color.watchBeatAttention : Color.secondary.opacity(0.22),
            isFlagged: isFlagged
        ))
    }

    /// Section cards on every page: the data-card surface without a stripe.
    func watchBeatPanel() -> some View {
        modifier(WatchBeatSurfaceModifier(stripe: nil, isFlagged: false))
    }
}

/// Large value with a short caption, used for key numbers. Highlighting uses the research-flag
/// yellow; everything else stays neutral.
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
            isHighlighted ? Color.watchBeatAttention.opacity(0.16) : Color.watchBeatInset,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Card title with a muted icon, shared by every card.
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

/// Heading that sits on the page canvas above a group of cards, with an optional trailing action.
struct WatchBeatGroupHeader<Accessory: View>: View {
    let title: String
    let accessory: Accessory

    init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.bold())
            Spacer(minLength: 8)
            accessory
                .font(.subheadline)
        }
        .padding(.horizontal, 4)
    }
}

extension WatchBeatGroupHeader where Accessory == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// Rounded-square symbol used at the start of rows and tiles.
struct WatchBeatIconBadge: View {
    let systemImage: String
    var tint: Color = .pink
    var background: Color?
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                background ?? tint.opacity(0.12),
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// Read-only capsule for a self-reported feeling or custom tag.
struct WatchBeatChip: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.pink.opacity(0.1), in: Capsule())
    }
}

/// Lays chips out left to right and wraps them onto new lines, instead of stretching them into
/// equal grid columns.
struct WatchBeatFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if maxWidth.isFinite, size.width > maxWidth {
                // An over-long chip wraps its own text rather than overflowing the row.
                size = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            if !current.items.isEmpty, current.width + spacing + size.width > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width += (current.items.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.items.append(Item(index: index, size: size))
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

/// Quiet multi-line footer that ends a page; the research disclaimer lives here, not in a card.
struct WatchBeatFootnote: View {
    let text: String
    var systemImage = "info.circle"

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}
