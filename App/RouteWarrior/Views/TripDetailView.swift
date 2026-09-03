import CoreLocation
import MapKit
import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import SwiftUI

struct TripDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(MapSettings.self) private var mapSettings
    @Environment(StoreService.self) private var store
    let record: TripRecord
    @Query private var allSnapshots: [SnapshotRecord]
    @Query private var allTrips: [TripRecord]
    @Query(sort: \PlaceRecord.createdAt) private var places: [PlaceRecord]
    @State private var showPaywall = false

    private var trip: Trip? { try? record.trip() }

    private func snapshot(id: UUID?) -> PlanSnapshot? {
        guard let id else { return nil }
        return allSnapshots.first { $0.id == id }.flatMap { try? $0.snapshot() }
    }

    /// The plan the driver saw at departure (the preferred provider's).
    private var snapshot: PlanSnapshot? { snapshot(id: record.snapshotID) }
    /// The other provider's plan for the same departure ("beat both").
    private var altSnapshot: PlanSnapshot? { snapshot(id: record.altSnapshotID) }

    private struct PlanEntry: Identifiable {
        let plan: PlanSnapshot
        let followed: Bool?
        var id: UUID { plan.id }
    }

    /// Every plan with its followed label, primary first.
    private var plans: [PlanEntry] {
        var result: [PlanEntry] = []
        if let snapshot { result.append(PlanEntry(plan: snapshot, followed: record.followedPlan)) }
        if let altSnapshot { result.append(PlanEntry(plan: altSnapshot, followed: record.followedAltPlan)) }
        return result
    }

    /// D-022: a provider's line is drawn only on that provider's map. The
    /// map is whichever surface the user chose; the other provider's plan
    /// appears as numbers in the Drive section instead.
    private var drawablePlan: PlanSnapshot? {
        plans.map(\.plan).first { $0.provider == mapSettings.provider.snapshotProvider }
    }

    private func scene(for trip: Trip) -> MapScene {
        MapScene(
            plans: plans.map(\.plan),
            trail: trip.points.map(\.coordinate),
            showsTraffic: false,
            camera: .fitContent
        )
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
            destinationSection
            statsSection
            if let trip, !trip.stopEvents.isEmpty {
                stopsSection(trip.stopEvents)
            }
            controlsSection
        }
        .navigationTitle(record.startedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: All drives to the same place

    private var destinationPlace: PlaceRecord? {
        guard let id = record.destinationPlaceID else { return nil }
        return places.first { $0.id == id }
    }

    /// This trip is one of many to the same place; the destination screen
    /// is where those are compared with each other, so offer the way in
    /// from here rather than only from the Places tab.
    @ViewBuilder
    private var destinationSection: some View {
        if let place = destinationPlace {
            let rank = DestinationAnalytics.rank(of: place.id, in: places.map(\.id)) ?? 0
            let allowed = store.policy.canAnalyzeDestination(atRank: rank, tier: store.tier)
            Section {
                if allowed {
                    NavigationLink {
                        DestinationDetailView(place: place)
                    } label: {
                        destinationLabel(place, locked: false)
                    }
                } else {
                    Button {
                        showPaywall = true
                    } label: {
                        destinationLabel(place, locked: true)
                    }
                    .tint(.primary)
                }
            } footer: {
                Text(allowed
                     ? "Every drive to \(place.name), with each route you have taken and how they compare."
                     : "Analyzing more destinations is part of Pro.")
            }
        }
    }

    private func tripsHereCount(_ place: PlaceRecord) -> Int {
        allTrips.filter { $0.destinationPlaceID == place.id }.count
    }

    private func destinationLabel(_ place: PlaceRecord, locked: Bool) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: locked ? "lock.fill" : "chart.bar.xaxis", color: locked ? Theme.pro : Theme.route)
            VStack(alignment: .leading, spacing: 2) {
                Text("All drives to \(place.name)")
                Text("\(tripsHereCount(place)) recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func routeMap(for trip: Trip) -> some View {
        MapSurfaceView(scene: scene(for: trip))
    }

    /// The same two strokes as the map, so the colours need no caption.
    private var mapLegend: some View {
        HStack(spacing: 18) {
            legendSwatch(Theme.route, dashed: false, label: "Your drive")
            if let drawablePlan {
                legendSwatch(Theme.google, dashed: true, label: "\(drawablePlan.provider.displayName)'s plan")
            } else if let first = plans.first {
                Text("\(first.plan.provider.displayName)'s plan: see below")
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

    /// The headline of the whole screen: did you beat the plan you saw?
    private func comparisonCard(snapshot: PlanSnapshot) -> some View {
        let delta = record.endedAt.timeIntervalSince(record.startedAt) - snapshot.trafficDuration
        let tone = TripTone.forTrip(deltaSeconds: delta, excluded: false)
        let name = snapshot.provider.displayName
        return HStack(spacing: 12) {
            IconTile(symbol: tone.symbol, color: tone.color, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(delta <= 0 ? "You beat \(name)'s ETA" : "\(name)'s ETA beat you")
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
            if plans.isEmpty {
                LabeledContent("Plan comparison", value: "None for this trip")
            }
            ForEach(plans) { entry in
                let name = entry.plan.provider.displayName
                let delta = record.endedAt.timeIntervalSince(record.startedAt) - entry.plan.trafficDuration
                LabeledContent("\(name)'s ETA was", value: Format.duration(entry.plan.trafficDuration))
                LabeledContent("You vs. \(name)") {
                    Text(Format.signedDelta(delta))
                        .foregroundStyle(delta <= 0 ? Theme.win : Theme.google)
                        .monospacedDigit()
                }
                if let followed = entry.followed {
                    LabeledContent("Followed \(name)'s route", value: followed ? "Yes" : "No — your own way")
                }
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
