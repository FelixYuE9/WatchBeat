import Foundation
import Observation
import WatchBeatHealthKit
import WatchBeatModels

@MainActor
@Observable
public final class ECGListViewModel {
    public private(set) var state: ECGListState = .idle

    private let repository: ECGRepository

    public init(repository: ECGRepository) {
        self.repository = repository
    }

    public func load() async {
        state = .loading
        let outcome = await repository.loadRecords()
        switch outcome {
        case .loaded(let records):
            state = records.isEmpty ? .noAccessibleRecords : .loaded(records)
        case .noAccessibleRecords:
            state = .noAccessibleRecords
        case .unavailable:
            state = .unavailable
        case .superseded, .cancelled:
            break
        case .failed(let message):
            state = .failed(message: message)
        }
    }

    /// Requests ECG read access only, then reloads. HealthKit reports no reliable read-denial state,
    /// so an empty result afterwards is presented as "no accessible records", never as denial.
    public func requestReadAccess() async {
        let outcome = await repository.prepareAuthorization()
        switch outcome {
        case .authorizationRequested:
            await load()
        case .unavailable:
            state = .unavailable
        case .failed(let message):
            state = .failed(message: message)
        }
    }

    public func makeDetailViewModel(for record: ECGRecord) -> ECGDetailViewModel {
        ECGDetailViewModel(repository: repository, record: record)
    }
}
