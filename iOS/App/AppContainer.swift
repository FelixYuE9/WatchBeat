import Observation
import SwiftUI
import WatchBeatHealthKit
import WatchBeatModels

/// Long-lived objects for the app scene. Created once and held by `@State` in `WatchBeatApp`.
@MainActor
@Observable
public final class AppContainer {
    public let repository: ECGRepository
    public let listViewModel: ECGListViewModel
    public let exampleMeasurement: ECGMeasurement?

    public init() {
        let repository = ECGRepository(reader: LiveHealthKitECGReader())
        self.repository = repository
        self.listViewModel = ECGListViewModel(repository: repository)
        self.exampleMeasurement = try? ECGExampleFactory.makeMeasurement()
    }
}
