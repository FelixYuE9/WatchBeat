import SwiftUI

public struct RootView: View {
    @AppStorage(MedicalDisclaimer.acceptanceKey) private var hasAcceptedDisclaimer = false
    @AppStorage(AppLanguage.storageKey) private var storedLanguage = AppLanguage.system.rawValue
    let container: AppContainer

    public init(container: AppContainer) {
        self.container = container
    }

    public var body: some View {
        Group {
            if hasAcceptedDisclaimer {
                AppHomeView(container: container)
            } else {
                DisclaimerView {
                    hasAcceptedDisclaimer = true
                }
            }
        }
        .environment(\.appLanguage, selectedLanguage)
        .environment(\.locale, selectedLanguage.locale)
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: storedLanguage) ?? .system
    }
}
