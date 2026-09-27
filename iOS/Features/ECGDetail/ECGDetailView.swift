import SwiftUI
import WatchBeatModels

public struct ECGDetailView: View {
    let viewModel: ECGDetailViewModel

    public init(viewModel: ECGDetailViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                metadataSection
                stateSection
                disclaimerSection
            }
            .padding()
        }
        .navigationTitle("ECG Record")
        .task { await viewModel.load() }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata").font(.headline)
            row("Start", viewModel.record.startDate.formatted(date: .abbreviated, time: .standard))
            row("Duration", String(format: "%.1f s", viewModel.record.durationSeconds))
            row("Apple classification", viewModel.record.classification.displayName)
            row("Average heart rate", heartRateText)
            row("Sampling frequency", samplingText)
            row("Declared measurements", "\(viewModel.record.declaredMeasurementCount)")
            row("Symptoms", viewModel.record.symptomsStatus.displayName)
        }
    }

    @ViewBuilder
    private var stateSection: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading voltage measurements…")
        case .loaded(let measurement):
            integritySection(measurement: measurement, incomplete: false)
        case .loadedWithIncompleteMeasurements(let measurement):
            integritySection(measurement: measurement, incomplete: true)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text("Measurement query failed").font(.headline)
                Text("Error: \(message)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Try again") { Task { await viewModel.load() } }
            }
        }
    }

    private func integritySection(measurement: ECGMeasurement, incomplete: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Measurements").font(.headline)
            row("Loaded samples", "\(measurement.integrity.sampleCount)")
            row("Missing voltages", "\(measurement.integrity.missingVoltageIndices.count)")
            row("Nominal rate", rateText(measurement.signal.nominalSamplingRateHz))
            row("Inferred rate", rateText(measurement.integrity.inferredSamplingRateHz))
            row("Timestamps strictly increasing", measurement.integrity.hasStrictlyIncreasingFiniteTimestamps ? "yes" : "no")

            if incomplete {
                Text("Incomplete measurement data")
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.orange)
                ForEach(measurement.issues, id: \.self) { issue in
                    Text("· \(issue.displayName)")
                        .font(.caption)
                }
            }

            Text("Beat analysis is not implemented yet: this milestone only reads and verifies data.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Research use only — not a diagnosis").font(.headline)
            Text(MedicalDisclaimer.english).font(.caption)
            Text(MedicalDisclaimer.chinese).font(.caption)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private var heartRateText: String {
        guard let heartRate = viewModel.record.averageHeartRateBPM else { return "not available" }
        return String(format: "%.0f BPM", heartRate)
    }

    private var samplingText: String {
        guard let rate = viewModel.record.samplingFrequencyHz else { return "not available" }
        return String(format: "%.0f Hz", rate)
    }

    private func rateText(_ rate: Double?) -> String {
        guard let rate else { return "not available" }
        return String(format: "%.1f Hz", rate)
    }
}
