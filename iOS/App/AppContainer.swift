import Observation
import SwiftUI
import WatchBeatHealthKit
import WatchBeatModels

/// Long-lived objects for the app scene. Created once and held by `@State` in `WatchBeatApp`.
@MainActor
@Observable
public final class AppContainer {
    public let repository: ECGRepository
    public let annotations: ECGAnnotationStore
    public let listViewModel: ECGListViewModel
    public let exampleMeasurement: ECGMeasurement?

    public init() {
        let repository = ECGRepository(
            reader: LiveHealthKitECGReader(),
            screeningStorage: ECGScreeningCacheFileStorage.standard()
        )
        self.repository = repository
        self.annotations = ECGAnnotationStore()
        self.listViewModel = ECGListViewModel(repository: repository)
        self.exampleMeasurement = try? ECGExampleFactory.makeMeasurement()
    }
}
