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

public extension View {
    func watchBeatCard() -> some View {
        padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.42), lineWidth: 0.7)
            }
    }
}
