import SwiftUI
import WatchBeatModels

public struct ECGListView: View {
    let viewModel: ECGListViewModel

    public init(viewModel: ECGListViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        content
            .navigationTitle("ECG Records")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Reload") {
                        Task { await viewModel.load() }
                    }
                }
            }
            .task { await viewModel.load() }
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
            )
        case .authorizationRequired:
            placeholder(
                title: "ECG read access has not been requested",
                message: "Only reading saved ECG records is requested. Nothing is written to Apple Health."
            ) {
                Button("Request ECG read access") {
                    Task { await viewModel.requestReadAccess() }
                }
                .buttonStyle(.borderedProminent)
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
                Button("Request ECG read access") {
                    Task { await viewModel.requestReadAccess() }
                }
            }
        case .loaded(let records):
            List {
                ForEach(records) { record in
                    NavigationLink(value: record) {
                        ECGRecordRow(record: record)
                    }
                }
            }
            .navigationDestination(for: ECGRecord.self) { record in
                ECGDetailView(viewModel: viewModel.makeDetailViewModel(for: record))
            }
        case .failed(let message):
            placeholder(
                title: "The ECG query failed",
                message: "Error: \(message)"
            ) {
                Button("Try again") {
                    Task { await viewModel.load() }
                }
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
