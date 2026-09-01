import CoreLocation
import MapKit
import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import SwiftUI

struct TripDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let record: TripRecord
    @Query private var allSnapshots: [SnapshotRecord]

    private var trip: Trip? { try? record.trip() }

    private var snapshot: PlanSnapshot? {
        guard let id = record.snapshotID else { return nil }
        return allSnapshots.first { $0.id == id }.flatMap { try? $0.snapshot() }
    }

    var body: some View {
        List {
            if let trip, trip.points.count >= 2 {
                Section {
                    routeMap(for: trip)
                        .frame(height: 260)
                        .listRowInsets(EdgeInsets())
                }
            }
            statsSection
            if let trip, !trip.stopEvents.isEmpty {
                stopsSection(trip.stopEvents)
            }
            controlsSection
        }
        .navigationTitle(record.startedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func routeMap(for trip: Trip) -> some View {
        Map {
            if let snapshot {
                MapPolyline(coordinates: snapshot.polyline.coordinates.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                })
                .stroke(.orange, style: StrokeStyle(lineWidth: 3, dash: [6, 6]))
            }
            MapPolyline(coordinates: trip.points.map {
                CLLocationCoordinate2D(
                    latitude: $0.coordinate.latitude,
                    longitude: $0.coordinate.longitude
                )
            })
            .stroke(.blue, lineWidth: 4)
        }
    }

    private var statsSection: some View {
        Section("Drive") {
            LabeledContent("Duration", value: Format.duration(record.endedAt.timeIntervalSince(record.startedAt)))
            LabeledContent("Distance", value: Format.distance(record.distanceM))
            LabeledContent("Moving", value: Format.duration(record.movingTime))
            LabeledContent("Idle", value: Format.duration(record.idleTime))
            if let trip {
                LabeledContent("Stops", value: "\(trip.stopEvents.count)")
            }
            LabeledContent("Recorded", value: record.sourceRaw == "manual" ? "Manually" : "Automatically")
            if let snapshot {
                let delta = record.endedAt.timeIntervalSince(record.startedAt) - snapshot.trafficDuration
                LabeledContent("Google's ETA was", value: Format.duration(snapshot.trafficDuration))
                LabeledContent("You vs. the ETA") {
                    Text(Format.signedDelta(delta))
                        .foregroundStyle(delta <= 0 ? .green : .orange)
                        .monospacedDigit()
                }
                if let followed = record.followedPlan {
                    LabeledContent("Followed Google's route", value: followed ? "Yes" : "No — your own way")
                }
            } else {
                LabeledContent("Google comparison", value: "None for this trip")
            }
        }
    }

    private func stopsSection(_ stops: [StopEvent]) -> some View {
        Section("Stops") {
            ForEach(Array(stops.enumerated()), id: \.offset) { _, stop in
                HStack {
                    Text(label(for: stop.cause))
                    Spacer()
                    Text(Format.duration(stop.duration))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var controlsSection: some View {
        Section {
            Toggle("Exclude from stats", isOn: excludedBinding)
            Button("Delete trip", role: .destructive) {
                context.delete(record)
                try? context.save()
                dismiss()
            }
        } footer: {
            Text("Exclude rides where you were a passenger so they never skew your averages.")
        }
    }

    private var excludedBinding: Binding<Bool> {
        Binding(
            get: { record.excludedFromStats },
            set: { newValue in
                record.excludedFromStats = newValue
                try? context.save()
            }
        )
    }

    private func label(for cause: StopEvent.Cause) -> String {
        switch cause {
        case .stopSign: "Stop sign (inferred)"
        case .signal: "Signal (inferred)"
        case .trafficQueue: "Traffic queue"
        case .unknown: "Stop"
        }
    }
}
