import SwiftUI
import WatchBeatModels

public struct ECGDetailView: View {
    @State private var viewModel: ECGDetailViewModel
    @State private var pendingExportKind: ECGExportKind?
    @State private var sharedExport: ECGTemporaryExportFile?
    @State private var showsExportError = false

    public init(viewModel: ECGDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
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
        .confirmationDialog(
            exportConfirmationTitle,
            isPresented: showsExportConfirmation,
            presenting: pendingExportKind
        ) { kind in
            Button("Continue to Share") {
                prepareExport(kind: kind)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(exportConfirmationMessage)
        }
        .sheet(item: $sharedExport) { file in
            #if canImport(UIKit)
            ECGShareSheet(file: file)
            #else
            Text("System sharing is available in the iPhone app.")
                .padding()
            #endif
        }
        .alert("Export could not be prepared", isPresented: $showsExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The temporary file was not retained. Please try again.")
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata").font(.headline)
            row("Source", sourceText)
            row("Start", startDateText)
            row("Duration", String(format: "%.1f s", viewModel.record.durationSeconds))
            row("Apple classification", appleClassificationText)
            row("Average heart rate", heartRateText)
            row("Sampling frequency", samplingText)
            row("Declared measurements", "\(viewModel.record.declaredMeasurementCount)")
            row("Symptoms", symptomsText)
        }
    }

    @ViewBuilder
    private var stateSection: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading voltage measurements…")
        case .loaded(let measurement):
            loadedSections(measurement: measurement, incomplete: false)
        case .loadedWithIncompleteMeasurements(let measurement):
            loadedSections(measurement: measurement, incomplete: true)
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

    private func loadedSections(measurement: ECGMeasurement, incomplete: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if measurement.source == .builtInSyntheticExample {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Built-in synthetic example", systemImage: "testtube.2")
                        .font(.headline)
                    Text("Generated for learning the app. This is not a person's ECG and cannot validate medical accuracy.")
                        .font(.caption)
                }
                .foregroundStyle(.orange)
            }
            ECGWaveformView(signal: measurement.signal)
            integritySection(measurement: measurement, incomplete: incomplete)
            exportSection(measurement: measurement)
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

            Text("Beat analysis is not implemented yet; the waveform display does not classify beats.")
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

    private func exportSection(measurement: ECGMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export").font(.headline)
            Label(
                exportNoticeText,
                systemImage: viewModel.source == .healthKit ? "lock.shield" : "testtube.2"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button(ECGExportKind.rawCSV.buttonTitle) {
                    pendingExportKind = .rawCSV
                }
                .buttonStyle(.borderedProminent)

                Button(ECGExportKind.metadataJSON.buttonTitle) {
                    pendingExportKind = .metadataJSON
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var showsExportConfirmation: Binding<Bool> {
        Binding(
            get: { pendingExportKind != nil },
            set: { isPresented in
                if !isPresented { pendingExportKind = nil }
            }
        )
    }

    private var sourceText: String {
        switch viewModel.source {
        case .healthKit: return "Apple Health"
        case .builtInSyntheticExample: return "Built-in synthetic example"
        }
    }

    private var startDateText: String {
        guard viewModel.source == .healthKit else { return "not applicable" }
        return viewModel.record.startDate.formatted(date: .abbreviated, time: .standard)
    }

    private var appleClassificationText: String {
        guard viewModel.source == .healthKit else { return "not applicable" }
        return viewModel.record.classification.displayName
    }

    private var symptomsText: String {
        guard viewModel.source == .healthKit else { return "not applicable" }
        return viewModel.record.symptomsStatus.displayName
    }

    private var exportNoticeText: String {
        if viewModel.source == .builtInSyntheticExample {
            return "This example is generated and contains no personal Health data."
        }
        return "Exports contain sensitive health data. Share only with people and apps you trust."
    }

    private var exportConfirmationTitle: String {
        viewModel.source == .builtInSyntheticExample
            ? "Share the synthetic example?"
            : "This export contains sensitive health data"
    }

    private var exportConfirmationMessage: String {
        if viewModel.source == .builtInSyntheticExample {
            return "The file is generated example data and is clearly labelled as synthetic."
        }
        return "Anyone you share it with may keep a copy. No file is created until you continue."
    }

    private func prepareExport(kind: ECGExportKind) {
        guard let measurement = viewModel.measurement else { return }
        do {
            sharedExport = try ECGTemporaryExportWriter.create(
                kind: kind,
                measurement: measurement
            )
        } catch {
            showsExportError = true
        }
        pendingExportKind = nil
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
