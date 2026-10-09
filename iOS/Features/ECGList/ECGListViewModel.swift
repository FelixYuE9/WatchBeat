import Foundation
import Observation
import WatchBeatHealthKit
import WatchBeatModels

@MainActor
@Observable
public final class ECGListViewModel {
    public private(set) var state: ECGListState = .authorizationRequired
    public private(set) var screeningStates: [UUID: ECGListScreeningState] = [:]
    public var filter = ECGRecordFilter()

    public var records: [ECGRecord] {
        guard case .loaded(let records) = state else { return [] }
        return records
    }

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
        ECGDetailViewModel(repository: repository, record: record) { [weak self] summary in
            guard let self, self.records.contains(where: { $0.id == record.id }) else { return }
            self.screeningStates[record.id] = .result(summary)
        }
    }

    public func screeningState(for record: ECGRecord) -> ECGListScreeningState? {
        screeningStates[record.id]
    }

    /// Both the overview and data page use the same compact screening results.
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
            // Results saved by an earlier launch appear at once, in a single update; only records
            // added since then have their voltages read and analyzed.
            let cached = await repository.cachedScreeningSummaries(for: records)
            guard !Task.isCancelled else { return }
            if !cached.isEmpty {
                var states = screeningStates
                for (id, summary) in cached { states[id] = .result(summary) }
                screeningStates = states
            }

            for record in records where cached[record.id] == nil {
                guard !Task.isCancelled else { return }
                let outcome = await repository.loadScreeningSummary(for: record)
                guard !Task.isCancelled else { return }

                switch outcome {
                case .loaded(let summary):
                    screeningStates[record.id] = .result(summary)
                case .failed:
                    // An overlapping detail read may already have published a valid summary.
                    if case .result = screeningStates[record.id] { break }
                    screeningStates[record.id] = .failed
                case .cancelled:
                    return
                }
            }
            await repository.flushScreeningCache()
            screeningTask = nil
        }
    }

    /// Deletes saved screening results. Records shown now keep their results until the next reload;
    /// after a relaunch every record is screened again.
    public func clearScreeningCache() async -> Bool {
        await repository.clearScreeningCache()
    }
}
