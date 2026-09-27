import SwiftUI
import WatchBeatModels

public struct ECGListView: View {
    @AppStorage("hasRequestedECGReadAccess") private var hasRequestedReadAccess = false
    let viewModel: ECGListViewModel
    let exampleMeasurement: ECGMeasurement?

    public init(viewModel: ECGListViewModel, exampleMeasurement: ECGMeasurement? = nil) {
        self.viewModel = viewModel
        self.exampleMeasurement = exampleMeasurement
    }

    public var body: some View {
        content
            .navigationTitle("ECG Records")
            .toolbar {
                if viewModel.canReload {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Reload") {
                            Task { await viewModel.load() }
                        }
                    }
                }
            }
            .task {
                guard hasRequestedReadAccess else { return }
                await viewModel.load()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading ECG metadata…")
        case .unavailable:
            placeholder(
                title: "HealthKit ECG is unavailable",
                message: "This device or OS version does not expose ECG records through HealthKit."
            ) {
                exampleLink
            }
        case .authorizationRequired:
            placeholder(
                title: "ECG read access has not been requested",
                message: "Only reading saved ECG records is requested. Nothing is written to Apple Health."
            ) {
                VStack(spacing: 12) {
                    Button("Request ECG read access") {
                        Task { await requestReadAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                    exampleLink
                }
            }
        case .noAccessibleRecords:
            placeholder(
                title: "No accessible ECG records",
                message: """
                    No ECG record was returned. This can mean no saved Apple Watch ECG exists, or that \
                    read access was not granted. HealthKit does not allow these to be distinguished, so \
                    this app never claims access was denied.
                    """
            ) {
                VStack(spacing: 12) {
                    Button("Request ECG read access") {
                        Task { await requestReadAccess() }
                    }
                    exampleLink
                }
            }
        case .loaded(let records):
            List {
                if exampleMeasurement != nil {
                    Section("Learn with an example") {
                        exampleLink
                    }
                }
                Section("Your Health records") {
                    ForEach(records) { record in
                        NavigationLink(value: record) {
                            ECGRecordRow(record: record)
                        }
                    }
                }
            }
            .navigationDestination(for: ECGRecord.self) { record in
                ECGDetailView(viewModel: viewModel.makeDetailViewModel(for: record))
            }
        case .failed(let message):
            placeholder(
                title: "Unable to access ECG records",
                message: "Error: \(message)"
            ) {
                VStack(spacing: 12) {
                    Button("Try again") {
                        Task { await requestReadAccess() }
                    }
                    exampleLink
                }
            }
        }
    }

    @ViewBuilder
    private var exampleLink: some View {
        if let exampleMeasurement {
            NavigationLink {
                ECGDetailView(viewModel: ECGDetailViewModel(example: exampleMeasurement))
            } label: {
                Label("Explore built-in synthetic ECG", systemImage: "waveform.path.ecg")
            }
        }
    }

    private func placeholder(
        title: String,
        message: String,
        @ViewBuilder action: () -> some View = { EmptyView() }
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.path.ecg")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            action()
        }
        .padding()
    }

    @MainActor
    private func requestReadAccess() async {
        if await viewModel.requestReadAccess() {
            hasRequestedReadAccess = true
        }
    }
}

public struct ECGRecordRow: View {
    let record: ECGRecord

    public init(record: ECGRecord) {
        self.record = record
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.startDate, format: .dateTime.year().month().day().hour().minute())
                .font(.headline)
            Text(record.classification.displayName)
                .font(.subheadline)
            Text("\(String(format: "%.1f", record.durationSeconds)) s · \(record.declaredMeasurementCount) measurements")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
