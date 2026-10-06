import ECGCore
import Foundation
import Observation
import WatchBeatHealthKit
import WatchBeatModels

@MainActor
@Observable
public final class ECGDetailViewModel {
    public let record: ECGRecord
    public let source: ECGMeasurementSource
    public private(set) var state: ECGDetailState = .idle

    private let repository: ECGRepository?

    public init(repository: ECGRepository, record: ECGRecord) {
        self.repository = repository
        self.record = record
        self.source = .healthKit
    }

    public init(example measurement: ECGMeasurement) {
        self.repository = nil
        self.record = measurement.record
        self.source = measurement.source
        self.state = measurement.isComplete
            ? .loaded(measurement)
            : .loadedWithIncompleteMeasurements(measurement)
    }

    public var measurement: ECGMeasurement? {
        switch state {
        case .loaded(let measurement), .loadedWithIncompleteMeasurements(let measurement):
            return measurement
        case .idle, .loading, .failed:
            return nil
        }
    }

    /// Markers always come from the same model report, never from source-specific annotations.
    public var waveformMarkers: [ECGWaveformMarker] {
        guard let measurement, measurement.analysis.status == .analyzed else { return [] }
        return measurement.analysis.beats.map { beat in
            ECGWaveformMarker(
                id: "model-r-\(beat.sampleIndex)",
                timeSeconds: beat.timeSeconds,
                label: beat.classification == .prematureUncertain
                    ? ECGWaveformMarker.prematureCandidateLabel
                    : "R",
                sampleIndex: beat.sampleIndex
            )
        }
    }

    public func load() async {
        guard let repository else { return }
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
