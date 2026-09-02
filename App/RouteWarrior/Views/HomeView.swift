import RouteWarriorStore
import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(RecordingPipeline.self) private var pipeline
    @Environment(LocationService.self) private var locationService
    @Environment(StoreService.self) private var store
    @State private var showPlan = false
    @State private var showDrive = false
    @State private var driveAfterPlan = false
    @State private var showPaywall = false
    @Query(sort: \TripRecord.startedAt, order: .reverse) private var trips: [TripRecord]
    @Query private var snapshots: [SnapshotRecord]

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
                                TripRowView(
                                    record: record,
                                    deltaSeconds: record.etaDeltaSeconds(in: snapshots)
                                )
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
            .sheet(isPresented: $showPlan, onDismiss: {
                // Present the drive view only after the sheet is gone; iOS
                // drops a presentation started mid-dismissal.
                if driveAfterPlan {
                    driveAfterPlan = false
                    showDrive = true
                }
            }) {
                PlanView { driveAfterPlan = store.policy.driveViewAvailable(for: store.tier) }
            }
            .fullScreenCover(isPresented: $showDrive) {
                DriveView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    private var statusCard: some View {
        let tint = Theme.statusTint(for: pipeline.recorderState)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconTile(
                    symbol: Theme.statusSymbol(for: pipeline.recorderState),
                    color: tint,
                    size: 40,
                    pulsing: pipeline.isRecording
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.headline)
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                recordButton
            }
            if pipeline.isRecording {
                Button {
                    if store.policy.driveViewAvailable(for: store.tier) {
                        showDrive = true
                    } else {
                        showPaywall = true
                    }
                } label: {
                    Label("Open the drive view", systemImage: "map.fill")
                }
                .buttonStyle(.bordered)
                .tint(tint)
                .font(.footnote)
            } else {
                Button {
                    showPlan = true
                } label: {
                    Label("Where to?", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .tint(tint)
                .font(.footnote)
            }
            if let outcome = pipeline.lastOutcome {
                Text(outcome)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let warning = LocationPrimer.warning(for: locationService.authorizationStatus) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.google)
                LocationFixButton(style: .bordered)
                    .font(.footnote)
            }
        }
        .padding(.vertical, 6)
        .tintedRow(tint)
    }

    private var statusText: String {
        switch pipeline.recorderState {
        case .idle: "Ready"
        case .armed: "Drive detected…"
        case .recording: "Recording"
        }
    }

    private var statusDetail: String {
        switch pipeline.recorderState {
        case .idle: "Waiting for the next drive"
        case .armed: "Confirming you're on the road"
        case .recording: "Tracking this drive"
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
        .tint(pipeline.isRecording ? Theme.recording : Theme.route)
    }
}

struct TripRowView: View {
    let record: TripRecord
    /// Actual duration minus Google's ETA (see `TripRecord.etaDeltaSeconds`);
    /// nil when the trip has no comparison.
    var deltaSeconds: Double? = nil

    private var tone: TripTone {
        .forTrip(deltaSeconds: deltaSeconds, excluded: record.excludedFromStats)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tone.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tone.color)
                .frame(width: 32, height: 32)
                .background(tone.color.opacity(0.14), in: Circle())
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
                    }
                    if let deltaSeconds {
                        Text("\(Format.signedDelta(deltaSeconds)) vs. ETA")
                            .foregroundStyle(tone.color)
                            .monospacedDigit()
                    } else if record.snapshotID == nil {
                        Text("no comparison")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
