import Foundation
import Observation
import WatchBeatHealthKit
import WatchBeatModels

public enum ECGListScreeningState: Equatable, Sendable {
    case checking
    case result(ECGScreeningSummary)
    case failed

    public var isFlagged: Bool {
        guard case .result(.prematureCandidates(count: _)) = self else { return false }
        return true
    }
}

@MainActor
@Observable
public final class ECGListViewModel {
    public private(set) var state: ECGListState = .authorizationRequired
    public private(set) var screeningStates: [UUID: ECGListScreeningState] = [:]

    private let repository: ECGRepository
    private var screeningTask: Task<Void, Never>?
    private var isScreeningRequested = false

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
        screeningTask?.cancel()
        screeningTask = nil
        screeningStates.removeAll(keepingCapacity: true)
        state = .loading
        let outcome = await repository.loadRecords()
        switch outcome {
        case .loaded(let records):
            state = records.isEmpty ? .noAccessibleRecords : .loaded(records)
            if isScreeningRequested, !records.isEmpty { startScreening(records) }
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

    public func screeningState(for record: ECGRecord) -> ECGListScreeningState? {
        screeningStates[record.id]
    }

    /// Defers voltage-heavy screening until the user actually visits the data page.
    public func startScreeningIfNeeded() {
        isScreeningRequested = true
        guard screeningTask == nil,
              screeningStates.isEmpty,
              case .loaded(let records) = state,
              !records.isEmpty else {
            return
        }
        startScreening(records)
    }

    private func startScreening(_ records: [ECGRecord]) {
        screeningStates = Dictionary(
            uniqueKeysWithValues: records.map { ($0.id, .checking) }
        )
        screeningTask = Task { [weak self] in
            guard let self else { return }
            for record in records {
                guard !Task.isCancelled else { return }
                let outcome = await repository.loadScreeningSummary(for: record)
                guard !Task.isCancelled else { return }

                switch outcome {
                case .loaded(let summary):
                    screeningStates[record.id] = .result(summary)
                case .failed:
                    screeningStates[record.id] = .failed
                case .cancelled:
                    return
                }
            }
            screeningTask = nil
        }
    }
}
