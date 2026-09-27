import SwiftUI

public struct RootView: View {
    @AppStorage(MedicalDisclaimer.acceptanceKey) private var hasAcceptedDisclaimer = false
    let container: AppContainer

    public init(container: AppContainer) {
        self.container = container
    }

    public var body: some View {
        Group {
            if hasAcceptedDisclaimer {
                NavigationStack {
                    ECGListView(viewModel: container.listViewModel)
                }
            } else {
                DisclaimerView {
                    hasAcceptedDisclaimer = true
                }
            }
        }
    }
}
