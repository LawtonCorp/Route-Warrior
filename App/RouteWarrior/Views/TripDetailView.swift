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
                    mapLegend
                }
            }
            if let snapshot {
                Section {
                    comparisonCard(snapshot: snapshot)
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
                .stroke(Theme.google, style: StrokeStyle(lineWidth: 3, dash: [6, 6]))
            }
            MapPolyline(coordinates: trip.points.map {
                CLLocationCoordinate2D(
                    latitude: $0.coordinate.latitude,
                    longitude: $0.coordinate.longitude
                )
            })
            .stroke(Theme.route, lineWidth: 4)
        }
    }

    /// The same two strokes as the map, so the colours need no caption.
    private var mapLegend: some View {
        HStack(spacing: 18) {
            legendSwatch(Theme.route, dashed: false, label: "Your drive")
            if snapshot != nil {
                legendSwatch(Theme.google, dashed: true, label: "Google's plan")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendSwatch(_ color: Color, dashed: Bool, label: String) -> some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 2))
                path.addLine(to: CGPoint(x: 24, y: 2))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, dash: dashed ? [4, 3] : []))
            .frame(width: 24, height: 4)
            Text(label)
        }
    }

    /// The headline of the whole screen: did you beat the plan?
    private func comparisonCard(snapshot: PlanSnapshot) -> some View {
        let delta = record.endedAt.timeIntervalSince(record.startedAt) - snapshot.trafficDuration
        let tone = TripTone.forTrip(deltaSeconds: delta, excluded: false)
        return HStack(spacing: 12) {
            IconTile(symbol: tone.symbol, color: tone.color, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(delta <= 0 ? "You beat Google's ETA" : "Google's ETA beat you")
                    .font(.headline)
                Text("\(Format.signedDelta(delta)) against a \(Format.duration(snapshot.trafficDuration)) plan")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .tintedRow(tone.color)
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
                        .foregroundStyle(delta <= 0 ? Theme.win : Theme.google)
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
                    Label {
                        Text(label(for: stop.cause))
                    } icon: {
                        Image(systemName: symbol(for: stop.cause))
                            .foregroundStyle(color(for: stop.cause))
                    }
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

    private func symbol(for cause: StopEvent.Cause) -> String {
        switch cause {
        case .stopSign: "octagon.fill"
        case .signal: "circle.fill"
        case .trafficQueue: "car.2.fill"
        case .unknown: "pause.circle.fill"
        }
    }

    private func color(for cause: StopEvent.Cause) -> Color {
        switch cause {
        case .stopSign: Theme.recording
        case .signal: Theme.armed
        case .trafficQueue: Theme.google
        case .unknown: Color.secondary
        }
    }
}
