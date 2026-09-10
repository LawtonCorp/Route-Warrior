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
            camera: .fitContent,
            userLocation: locationService.lastKnownCoordinate
        )
    }

    var body: some View {
        NavigationStack {
            List {
                // "Where to?" is the first thing on the screen (D-046);
                // the recorder speaks only when it has something to say.
                Section {
                    searchField
                    if showsSuggestions { suggestionRows }
                    if let warning = LocationPrimer.warning(for: locationService.authorizationStatus) {
                        locationWarning(warning)
                    }
                }
                Section {
                    MapSurfaceView(scene: scene)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        // A gutter each side, so a finger can scroll the
                        // screen without landing on the map.
                        .listRowInsets(EdgeInsets(top: 4, leading: 28, bottom: 4, trailing: 28))
                        // The map draws its own edges; the row's card
                        // would only frame it in white.
                        .listRowBackground(Color.clear)
                    if planner.hasDestination { planRows }
                } header: {
                    if let destination = planner.destination {
                        Text("To \(destination.name)")
                    }
                }
                // Its own card, so it never reads as the map's footer (D-047).
                if HomeLayout.showsRecorderRow(pipeline.recorderState) {
                    Section { recorderRow }
                }
                if planner.hasDestination, !pipeline.isRecording { goSection }
                savedPlacesSection
            }
            .navigationTitle("Route Rebel")
            // Inline, so Record sits on the title's line rather than
            // floating above a large title (D-047).
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if HomeLayout.showsRecordButton(
                    hasDestination: planner.hasDestination, state: pipeline.recorderState
                ) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Record", systemImage: "record.circle") {
                            pipeline.startManualRecording()
                        }
                        .tint(Theme.recording)
                    }
                }
            }
            .listSectionSpacing(.compact)
            .fullScreenCover(isPresented: $showDrive) { DriveView() }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .onAppear { primeLocation() }
            .onChange(of: locationService.lastKnownCoordinate == nil) {
                primeLocation()
                // The fix arrived after the destination was chosen.
                if planner.hasDestination, planner.plans.isEmpty, !planner.loading { fetchPlans() }
            }
            .onChange(of: pipeline.isRecording) { was, now in
                // The trip is saved; the route it was driven against has
                // nothing left to say on the Plan tab (D-041).
                if DrivePlanner.planEnds(recordingWas: was, now: now, hasDestination: planner.hasDestination) {
                    clearSearch()
                }
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
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Theme.route.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var suggestionRows: some View {
        ForEach(matchingPlaces) { place in
            let kind = Place.Kind(stored: place.kindRaw)
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
            let detail = SuggestionDetail.detailLine(for: suggestion)
            Button {
                choose(suggestion)
            } label: {
                HStack(spacing: 12) {
                    IconTile(symbol: "mappin", color: Theme.route, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                        if !detail.isEmpty {
                            Text(detail)
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
                turns: TurnCounter.count(along: shown.polyline),
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
                        turns: TurnCounter.count(along: alternate.polyline),
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
        } else if let other = planner.plans.first {
            // Plans arrived, but not from the provider whose map is on
            // screen. Say so instead of showing an empty map, and show
            // what did come back.
            if surface == .googleRoutes, !store.policy.googleComparisonAvailable(for: store.tier) {
                // Not a failure: Google's plan is the Pro comparison (D-050).
                ProLockRow(
                    title: "Google's plan is part of Pro",
                    detail: "Apple's plan is your baseline for now. Pro puts Google on the scoreboard too."
                ) { showPaywall = true }
            } else {
                Label(
                    "\(surface.displayName) returned no plan for this trip. Settings → Recorder log says why.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(Theme.google)
            }
            planRow(
                title: "\(other.provider.displayName)'s plan",
                eta: other.trafficDuration,
                distance: other.distanceM,
                turns: TurnCounter.count(along: other.polyline),
                highlighted: false
            )
        }
    }

    /// ETA, distance and turns per plan: the turns are counted from the
    /// plan's own line (D-043), so two plans can be weighed by how many
    /// lefts each asks for, not only by the minutes the provider claims.
    private func planRow(
        title: String,
        eta: TimeInterval,
        distance: Double,
        turns: TurnCount,
        highlighted: Bool
    ) -> some View {
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
                Text(TurnText.summary(turns))
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
                    Label(planner.goTitle, systemImage: "car.fill")
                        .font(.headline)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.route)
            .listRowBackground(Color.clear)
        } footer: {
            Text(goFooter)
        }
    }

    /// The Go button never waits for the providers (D-044): while they
    /// are still being asked, the footer says the plan will catch up.
    private var goFooter: String {
        let base = mapSettings.navigateWithAppleMaps
            ? "Recording starts now, then Apple Maps takes over for turn-by-turn — on CarPlay too. Route Rebel keeps recording in the background, and the plan you left with stays the baseline."
            : "Recording starts now. Whatever plan you leave with is the baseline the drive is judged against. The live drive view and reroute are part of Pro; the trip records and compares either way."
        return planner.loading
            ? "Plans are still loading. Go now and they become the baseline when they arrive. " + base
            : base
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
                    let kind = Place.Kind(stored: place.kindRaw)
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

    // MARK: The recorder, beneath the routes

    /// One line, only while the recorder is doing something (D-046):
    /// armed reads as a caption, recording carries Stop and the drive
    /// view. An idle recorder shows nothing — "Ready" said nothing the
    /// empty field did not.
    private var recorderRow: some View {
        let tint = Theme.statusTint(for: pipeline.recorderState)
        return HStack(spacing: 10) {
            if pipeline.isRecording {
                BlinkingDot(color: tint)
            } else {
                IconTile(symbol: Theme.statusSymbol(for: pipeline.recorderState), color: tint, size: 24)
            }
            Text(pipeline.isRecording ? "Rec" : "Drive detected — confirming you're on the road")
                .font(pipeline.isRecording ? .subheadline.weight(.semibold) : .footnote)
                .foregroundStyle(pipeline.isRecording ? .primary : .secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            if pipeline.isRecording {
                Button {
                    if store.policy.driveViewAvailable(for: store.tier) {
                        showDrive = true
                    } else {
                        showPaywall = true
                    }
                } label: {
                    Label("Drive view", systemImage: "map.fill")
                }
                .buttonStyle(.bordered)
                .tint(tint)
                Button("Stop") {
                    pipeline.stopManualRecording()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.recording)
            }
        }
        .controlSize(.small)
        .padding(.vertical, 2)
        .tintedRow(tint)
    }

    /// The permission warning is the one recorder message that must stay
    /// on screen while it applies; it sits under the field, not in a card.
    private func locationWarning(_ warning: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.google)
            LocationFixButton(style: .bordered)
                .font(.footnote)
        }
        .padding(.vertical, 2)
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

    /// A row that already knows where it is goes straight to the plan;
    /// a bare completion is looked up first (D-040).
    @MainActor
    private func choose(_ suggestion: AddressSuggestion) {
        if let coordinate = suggestion.coordinate {
            select(DrivePlanner.Destination(name: suggestion.title, coordinate: coordinate, placeID: nil))
        } else {
            resolve(suggestion.query, title: suggestion.title)
        }
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
        // Asked from the departure point, before the drive began: if Go is
        // tapped before the answer lands, the answer is still this
        // departure's plan (D-044). A fetch begun mid-drive is not.
        let askedBeforeDeparture = !pipeline.isRecording
        Task {
            let fetched = await pipeline.computePlans(
                from: origin, to: destination.coordinate, destinationPlaceID: destination.placeID
            )
            planner.finish(with: fetched, for: destination)
            if askedBeforeDeparture, planner.destination == destination {
                pipeline.adoptDeparturePlans(fetched)
            }
        }
    }

    @MainActor
    private func go() {
        // Recording starts first, whatever happens next: the hand-off
        // sends the driver to another app, and the drive still has to be
        // recorded and compared.
        pipeline.startPlannedDrive(with: planner.plans)
        if mapSettings.navigateWithAppleMaps, let destination = planner.destination,
           AppleMapsHandoff.navigate(to: destination.coordinate, named: destination.name) {
            return
        }
        if store.policy.driveViewAvailable(for: store.tier) {
            showDrive = true
        }
    }
}
