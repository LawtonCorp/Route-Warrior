import CoreLocation
import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import SwiftUI

/// FR-20: pick a destination, see the plans, go. The map is whichever
/// surface the user chose (FR-19); that provider's route is drawn and any
/// other provider's plan is shown as numbers (D-022 §9.2). Free for every
/// tier — the live drive view after "Go" is the Pro part.
struct PlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RecordingPipeline.self) private var pipeline
    @Environment(LocationService.self) private var locationService
    @Environment(MapSettings.self) private var mapSettings
    @Query(sort: \PlaceRecord.createdAt) private var places: [PlaceRecord]

    /// Called after recording has started from the chosen plans.
    let onStarted: () -> Void

    private struct Destination: Equatable {
        var name: String
        var coordinate: Coordinate
        var placeID: UUID?
    }

    @State private var destination: Destination?
    @State private var plans: [PlanSnapshot] = []
    @State private var loading = false
    @State private var failed = false
    @State private var addressQuery = ""
    @State private var completer = AddressCompleter()

    private var surfaceProvider: PlanSnapshot.Provider { mapSettings.provider.snapshotProvider }
    /// The plan drawn on the chosen surface.
    private var shownPlan: PlanSnapshot? { plans.first { $0.provider == surfaceProvider } }
    private var otherPlans: [PlanSnapshot] { plans.filter { $0.provider != surfaceProvider } }

    private var scene: MapScene {
        MapScene(plans: plans, destinationName: destination?.name, camera: .fitContent)
    }

    var body: some View {
        NavigationStack {
            List {
                destinationSection
                if destination != nil {
                    planSection
                    goSection
                }
            }
            .navigationTitle("Plan a drive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let here = locationService.lastKnownCoordinate {
                    completer.focus(on: here)
                } else {
                    locationService.requestOneShotLocation()
                }
            }
            .onChange(of: locationService.lastKnownCoordinate == nil) {
                // The fix arrived after the destination was chosen.
                if destination != nil, plans.isEmpty, !loading { fetchPlans() }
            }
            .onChange(of: addressQuery) { _, newValue in
                completer.update(query: newValue)
            }
        }
    }

    // MARK: Destination

    private var destinationSection: some View {
        Section {
            ForEach(places) { place in
                let kind = Place.Kind(rawValue: place.kindRaw) ?? .custom
                Button {
                    choose(Destination(
                        name: place.name,
                        coordinate: Coordinate(latitude: place.latitude, longitude: place.longitude),
                        placeID: place.id
                    ))
                } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: kind.symbol, color: kind.color, size: 30)
                        Text(place.name)
                        Spacer()
                        if destination?.placeID == place.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.win)
                        }
                    }
                }
                .tint(.primary)
            }
            TextField("Or search an address", text: $addressQuery)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { resolve(addressQuery) }
            ForEach(completer.suggestions) { suggestion in
                Button {
                    resolve(suggestion.query, title: suggestion.title)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(.primary)
            }
        } header: {
            Text("Where to?")
        } footer: {
            if locationService.lastKnownCoordinate == nil {
                Text("Waiting for your location…")
            }
        }
    }

    // MARK: Plan

    private var planSection: some View {
        Section {
            if let shownPlan {
                MapSurfaceView(scene: scene)
                    .frame(height: 300)
                    .listRowInsets(EdgeInsets())
                planRow(
                    title: "\(shownPlan.provider.displayName)'s plan",
                    eta: shownPlan.trafficDuration,
                    distance: shownPlan.distanceM,
                    highlighted: true
                )
                ForEach(Array(shownPlan.alternates.enumerated()), id: \.offset) { index, alternate in
                    Button {
                        promote(index)
                    } label: {
                        planRow(
                            title: "Alternate \(index + 1)",
                            eta: alternate.trafficDuration,
                            distance: alternate.polyline.lengthMeters,
                            highlighted: false
                        )
                    }
                    .tint(.primary)
                }
            } else if loading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Asking for plans…")
                        .foregroundStyle(.secondary)
                }
            } else if failed {
                Text("No plan came back. Check the connection and try again, or drive anyway — the trip still records.")
                    .foregroundStyle(.secondary)
            }
            ForEach(otherPlans, id: \.id) { plan in
                planRow(
                    title: "\(plan.provider.displayName)'s plan (compared, not drawn here)",
                    eta: plan.trafficDuration,
                    distance: plan.distanceM,
                    highlighted: false
                )
            }
        } header: {
            Text(destination.map { "To \($0.name)" } ?? "Plan")
        } footer: {
            if shownPlan != nil {
                Text("Tap an alternate to make it the plan. Whatever you leave with is the baseline the drive is judged against — leaving it on the road is the whole idea.")
            }
        }
    }

    private func planRow(title: String, eta: TimeInterval, distance: Double, highlighted: Bool) -> some View {
        HStack {
            Text(title)
                .font(highlighted ? .headline : .body)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.duration(eta))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(highlighted ? Theme.route : .primary)
                Text(Format.distance(distance))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var goSection: some View {
        Section {
            Button {
                go()
            } label: {
                HStack {
                    Spacer()
                    Label(plans.isEmpty ? "Drive without a plan" : "Go", systemImage: "car.fill")
                        .font(.headline)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.route)
            .disabled(loading || destination == nil)
            .listRowBackground(Color.clear)
        } footer: {
            Text("Recording starts now. The live drive view and reroute are part of Pro; the trip records and compares either way.")
        }
    }

    // MARK: Actions

    @MainActor
    private func choose(_ chosen: Destination) {
        destination = chosen
        plans = []
        failed = false
        fetchPlans()
    }

    @MainActor
    private func fetchPlans() {
        guard let destination, let origin = locationService.lastKnownCoordinate else {
            locationService.requestOneShotLocation()
            return
        }
        loading = true
        Task {
            let fetched = await pipeline.computePlans(
                from: origin, to: destination.coordinate, destinationPlaceID: destination.placeID
            )
            plans = fetched
            loading = false
            failed = fetched.isEmpty
        }
    }

    @MainActor
    private func promote(_ index: Int) {
        guard let shownPlan else { return }
        plans = plans.map { $0.id == shownPlan.id ? $0.promotingAlternate(at: index) : $0 }
    }

    @MainActor
    private func resolve(_ text: String, title: String? = nil) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let near = locationService.lastKnownCoordinate
        Task {
            guard let found = await AddressCompleter.resolve(query, near: near) else {
                failed = true
                return
            }
            addressQuery = found.address
            completer.update(query: "")
            choose(Destination(name: title ?? found.name, coordinate: found.coordinate, placeID: nil))
        }
    }

    @MainActor
    private func go() {
        pipeline.startPlannedDrive(with: plans)
        onStarted()
        dismiss()
    }
}
