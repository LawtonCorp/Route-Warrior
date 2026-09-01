import RouteWarriorStore
import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(RecordingPipeline.self) private var pipeline
    @Environment(LocationService.self) private var locationService
    @Query(sort: \TripRecord.startedAt, order: .reverse) private var trips: [TripRecord]

    private var today: [TripRecord] {
        trips.filter { Calendar.current.isDateInToday($0.startedAt) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    statusCard
                }
                Section("Today") {
                    if today.isEmpty {
                        Text("No trips yet today.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(today) { record in
                            NavigationLink(value: record.id) {
                                TripRowView(record: record)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Route Warrior")
            .navigationDestination(for: UUID.self) { id in
                if let record = trips.first(where: { $0.id == id }) {
                    TripDetailView(record: record)
                }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(pipeline.isRecording ? Color.red : Color.secondary)
                    .frame(width: 10, height: 10)
                Text(statusText)
                    .font(.headline)
                Spacer()
                recordButton
            }
            if let outcome = pipeline.lastOutcome {
                Text(outcome)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if locationService.authorizationStatus == .notDetermined
                || locationService.authorizationStatus == .denied {
                Text("Location permission is required to record drives — see Settings.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        switch pipeline.recorderState {
        case .idle: "Ready"
        case .armed: "Drive detected…"
        case .recording: "Recording"
        }
    }

    private var recordButton: some View {
        Button {
            if pipeline.isRecording {
                pipeline.stopManualRecording()
            } else {
                pipeline.startManualRecording()
            }
        } label: {
            Text(pipeline.isRecording ? "Stop" : "Record")
        }
        .buttonStyle(.borderedProminent)
        .tint(pipeline.isRecording ? .red : .accentColor)
    }
}

struct TripRowView: View {
    let record: TripRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(record.startedAt, format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
                    .font(.subheadline)
                Spacer()
                Text(Format.duration(record.endedAt.timeIntervalSince(record.startedAt)))
                    .font(.subheadline.monospacedDigit())
            }
            HStack(spacing: 8) {
                Text(Format.distance(record.distanceM))
                if record.excludedFromStats {
                    Text("excluded")
                        .foregroundStyle(.orange)
                }
                if record.snapshotID == nil {
                    Text("no comparison")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
