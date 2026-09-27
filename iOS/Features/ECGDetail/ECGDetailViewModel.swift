import Foundation
import Observation
import WatchBeatHealthKit
import WatchBeatModels

@MainActor
@Observable
public final class ECGDetailViewModel {
    public let record: ECGRecord
    public private(set) var state: ECGDetailState = .idle

    private let repository: ECGRepository

    public init(repository: ECGRepository, record: ECGRecord) {
        self.repository = repository
        self.record = record
    }

    public func load() async {
        state = .loading
        let outcome = await repository.loadMeasurements(for: record)
        switch outcome {
        case .loaded(let measurement):
            state = measurement.isComplete
                ? .loaded(measurement)
                : .loadedWithIncompleteMeasurements(measurement)
        case .failed(let message):
            state = .failed(message: message)
        case .superseded, .cancelled:
            break
        }
    }
}
