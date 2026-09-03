import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import SwiftUI

/// FR-20 lives here now: the destination is typed straight into the
/// "Where to?" field, the map sits under it, and the saved places sit
/// under the map. There is no plan sheet to open — the Home screen *is*
/// the planning surface (D-026).
struct HomeView: View {
    @Environment(RecordingPipeline.self) private var pipeline
    @Environment(LocationService.self) private var locationService
    @Environment(StoreService.self) private var store
    @Environment(MapSettings.self) private var mapSettings
    @Query(sort: \PlaceRecord.createdAt) private var places: [PlaceRecord]

    @State private var planner = DrivePlanner()
    @State private var query = ""
    @State private var completer = AddressCompleter()
    @State private var resolving = false
    @State private var showDrive = false
    @State private var showPaywall = false
    @FocusState private var searchFocused: Bool

    private var surface: PlanSnapshot.Provider { mapSettings.provider.snapshotProvider }

    /// Suggestions belong to an active search, not to a destination the
    /// driver has already picked.
    private var showsSuggestions: Bool {
        searchFocused && !query.isEmpty && query != planner.destination?.name
    }

    /// Saved places matching what has been typed, so a place is reachable
    /// from the field as well as from the list under the map.
    private var matchingPlaces: [PlaceRecord] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return places.filter {
            $0.name.localizedCaseInsensitiveContains(text)
                || $0.address.localizedCaseInsensitiveContains(text)
        }
    }

    private var scene: MapScene {
        MapScene(
            plans: planner.plans,
            trail: pipeline.isRecording ? pipeline.liveTrack.map(\.coordinate) : [],
            destinationName: planner.destination?.name,
            camera: planner.plans.isEmpty ? .followUser : .fitContent
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section { statusCard }
                Section {
                    searchField
                    if showsSuggestions { suggestionRows }
                }
                Section {
                    MapSurfaceView(scene: scene)
                        .frame(height: 300)
                        .listRowInsets(EdgeInsets())
                    if planner.hasDestination { planRows }
                } header: {
                    if let destination = planner.destination {
                        Text("To \(destination.name)")
                    }
                }
                if planner.hasDestination, !pipeline.isRecording { goSection }
                savedPlacesSection
            }
            .navigationTitle("Route Warrior")
            .fullScreenCover(isPresented: $showDrive) { DriveView() }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .onAppear { primeLocation() }
            .onChange(of: locationService.lastKnownCoordinate == nil) {
                primeLocation()
                // The fix arrived after the destination was chosen.
                if planner.hasDestination, planner.plans.isEmpty, !planner.loading { fetchPlans() }
            }
            .onChange(of: query) { _, newValue in
                // Writing the chosen name back into the field is not a
                // new search.
                guard newValue != planner.destination?.name else { return }
                completer.update(query: newValue)
            }
        }
    }

    // MARK: Where to?

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.route)
            TextField("Where to?", text: $query)
                .font(.title3)
                .focused($searchFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { resolve(query) }
            if resolving {
                ProgressView()
            } else if !query.isEmpty {
                Button {
                    clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the destination")
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Theme.route.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var suggestionRows: some View {
        ForEach(matchingPlaces) { place in
            let kind = Place.Kind(rawValue: place.kindRaw) ?? .custom
            Button {
                choose(place)
            } label: {
                HStack(spacing: 12) {
                    IconTile(symbol: kind.symbol, color: kind.color, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                        if !place.address.isEmpty {
                            Text(place.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .tint(.primary)
        }
        ForEach(completer.suggestions) { suggestion in
            Button {
                resolve(suggestion.query, title: suggestion.title)
            } label: {
                HStack(spacing: 12) {
                    IconTile(symbol: "mappin", color: Theme.route, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .tint(.primary)
        }
    }

    // MARK: The plan under the map

    @ViewBuilder
    private var planRows: some View {
        if let shown = planner.plan(on: surface) {
            planRow(
                title: "\(shown.provider.displayName)'s plan",
                eta: shown.trafficDuration,
                distance: shown.distanceM,
                highlighted: true
            )
            ForEach(Array(shown.alternates.enumerated()), id: \.offset) { index, alternate in
                Button {
                    planner.promote(alternate: index, on: surface)
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
        } else if planner.loading {
            HStack(spacing: 10) {
                ProgressView()
                Text("Asking for plans…")
                    .foregroundStyle(.secondary)
            }
        } else if planner.failed {
            Text("No plan came back. Check the connection and try again, or drive anyway — the trip still records.")
                .foregroundStyle(.secondary)
        }
        ForEach(planner.others(on: surface), id: \.id) { plan in
            planRow(
                title: "\(plan.provider.displayName)'s plan (compared, not drawn here)",
                eta: plan.trafficDuration,
                distance: plan.distanceM,
                highlighted: false
            )
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
                    Label(planner.plans.isEmpty ? "Drive without a plan" : "Go", systemImage: "car.fill")
                        .font(.headline)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.route)
            .disabled(planner.loading)
            .listRowBackground(Color.clear)
        } footer: {
            Text("Recording starts now. Whatever plan you leave with is the baseline the drive is judged against. The live drive view and reroute are part of Pro; the trip records and compares either way.")
        }
    }

    // MARK: Saved places, under the map

    private var savedPlacesSection: some View {
        Section {
            if places.isEmpty {
                Text("No saved places yet. Add home, work, and school in the Places tab for one-tap destinations.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(places) { place in
                    let kind = Place.Kind(rawValue: place.kindRaw) ?? .custom
                    Button {
                        choose(place)
                    } label: {
                        HStack(spacing: 12) {
                            IconTile(symbol: kind.symbol, color: kind.color, size: 30)
                            Text(place.name)
                            Spacer()
                            if planner.destination?.placeID == place.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.win)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
        } header: {
            Text("Saved places")
        }
    }

    // MARK: Status

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

    // MARK: Actions

    @MainActor
    private func primeLocation() {
        if let here = locationService.lastKnownCoordinate {
            completer.focus(on: here)
        } else {
            locationService.requestOneShotLocation()
        }
    }

    @MainActor
    private func clearSearch() {
        query = ""
        completer.update(query: "")
        planner.clear()
    }

    @MainActor
    private func choose(_ place: PlaceRecord) {
        select(DrivePlanner.Destination(
            name: place.name,
            coordinate: Coordinate(latitude: place.latitude, longitude: place.longitude),
            placeID: place.id
        ))
    }

    @MainActor
    private func select(_ destination: DrivePlanner.Destination) {
        planner.start(destination)
        query = destination.name
        completer.update(query: "")
        searchFocused = false
        fetchPlans()
    }

    @MainActor
    private func resolve(_ text: String, title: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !resolving else { return }
        resolving = true
        let near = locationService.lastKnownCoordinate
        Task {
            let found = await AddressCompleter.resolve(trimmed, near: near)
            resolving = false
            guard let found else { return }
            select(DrivePlanner.Destination(
                name: title ?? found.name, coordinate: found.coordinate, placeID: nil
            ))
        }
    }

    @MainActor
    private func fetchPlans() {
        guard let destination = planner.destination else { return }
        guard let origin = locationService.lastKnownCoordinate else {
            locationService.requestOneShotLocation()
            return
        }
        planner.beginFetch()
        Task {
            let fetched = await pipeline.computePlans(
                from: origin, to: destination.coordinate, destinationPlaceID: destination.placeID
            )
            planner.finish(with: fetched, for: destination)
        }
    }

    @MainActor
    private func go() {
        pipeline.startPlannedDrive(with: planner.plans)
        if store.policy.driveViewAvailable(for: store.tier) {
            showDrive = true
        }
    }
}
