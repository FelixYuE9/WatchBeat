import SwiftUI

public enum AppTab: Hashable {
    case overview
    case records
    case settings
}

public struct AppHomeView: View {
    @AppStorage("hasRequestedECGReadAccess") private var hasRequestedReadAccess = false
    @State private var selectedTab: AppTab = .overview
    let container: AppContainer
    @Environment(\.appLanguage) private var language

    public init(container: AppContainer) {
        self.container = container
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                OverviewView(
                    viewModel: container.listViewModel,
                    exampleMeasurement: container.exampleMeasurement,
                    selectedTab: $selectedTab
                )
            }
            .tabItem {
                Label(
                    language.text("Overview", "概览"),
                    systemImage: "house.fill"
                )
            }
            .tag(AppTab.overview)

            NavigationStack {
                ECGListView(
                    viewModel: container.listViewModel,
                    exampleMeasurement: container.exampleMeasurement
                )
            }
            .tabItem {
                Label(language.text("Data", "数据"), systemImage: "waveform.path.ecg")
            }
            .tag(AppTab.records)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(language.text("Settings", "设置"), systemImage: "gearshape.fill")
            }
            .tag(AppTab.settings)
        }
        .environment(container.annotations)
        .tint(.pink)
        .onChange(of: selectedTab) { _, newTab in
            guard newTab == .records || newTab == .overview else { return }
            container.listViewModel.startScreeningIfNeeded()
        }
        .task {
            container.listViewModel.startScreeningIfNeeded()
            guard hasRequestedReadAccess else { return }
            await container.listViewModel.load()
        }
    }
}
