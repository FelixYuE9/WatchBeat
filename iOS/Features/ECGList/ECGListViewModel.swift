import Foundation
import Observation
import WatchBeatHealthKit
import WatchBeatModels

@MainActor
@Observable
public final class ECGListViewModel {
    public private(set) var state: ECGListState = .authorizationRequired

    private let repository: ECGRepository

    public init(repository: ECGRepository) {
        self.repository = repository
    }

    public var canReload: Bool {
        switch state {
        case .loaded, .noAccessibleRecords:
            return true
        case .idle, .loading, .unavailable, .authorizationRequired, .failed:
            return false
        }
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
    @discardableResult
    public func requestReadAccess() async -> Bool {
        state = .loading
        let outcome = await repository.prepareAuthorization()
        switch outcome {
        case .authorizationRequested:
            await load()
            return true
        case .unavailable:
            state = .unavailable
            return false
        case .failed(let message):
            state = .failed(message: message)
            return false
        }
    }

    public func makeDetailViewModel(for record: ECGRecord) -> ECGDetailViewModel {
        ECGDetailViewModel(repository: repository, record: record)
    }
}
