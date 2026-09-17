import Charts
import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import SwiftUI

/// The analytics screen (FR-12/FR-13/FR-14): verdict card, variants with
/// stop/signal inventories, the weekday × time heatmap, and the monthly
/// trend — all computed by kit engines over this destination's history.
struct DestinationDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(StoreService.self) private var store
    let place: PlaceRecord
    @State private var overpass = OverpassServiceHolder()
    @State private var showPaywall = false

    /// The verdict card is free; the heatmap, the trend and the route
    /// race are Pro (D-050), shown blurred so the shape is visible.
    private var deepLocked: Bool { !store.policy.deepAnalyticsAvailable(for: store.tier) }

    @Query private var allTrips: [TripRecord]
    @Query private var allVariants: [VariantRecord]
    @Query private var allSnapshots: [SnapshotRecord]
    /// For naming where each route starts (D-075). Unsorted on purpose —
    /// this is a lookup by id, not a list.
    @Query private var allPlaces: [PlaceRecord]

    /// Which starting point the screen is answering for (D-076). Nil
    /// until the driver picks, so the default follows the data rather
    /// than being frozen at whatever it was when the screen opened.
    @State private var picked: DestinationScope.Selection?

    /// Every drive that ended here, as stored. Nothing is decoded to
    /// build this (D-077) — the picker and the scope are answered from
    /// columns, and only the drives that survive the scope are turned
    /// into kit values.
    private var recordsHere: [TripRecord] {
        allTrips.filter { $0.destinationPlaceID == place.id }
    }

    private var origins: [DestinationScope.Origin] {
        DestinationScope.origins(
            countingOriginsOf: recordsHere.map(\.originPlaceID), places: allPlaces
        )
    }

    private var scope: DestinationScope.Selection {
        DestinationScope.resolved(
            picked ?? DestinationScope.defaultSelection(for: origins), in: origins
        )
    }

    /// How many drives here the current scope leaves out, for the footer.
    /// Counted, not decoded.
    private var unscopedDriveCount: Int {
        let scope = self.scope
        return recordsHere.filter { !DestinationScope.admits(originPlaceID: $0.originPlaceID, in: scope) }.count
    }

    /// Everything below reads these two, so scoping them scopes the
    /// verdict, the stats, the race, the recommendation, the heatmap and
    /// the trend in one place. Narrowed before decoding: a drive outside
    /// the scope never has its track read off disk.
    private var trips: [Trip] {
        let scope = self.scope
        return recordsHere
            .filter { DestinationScope.admits(originPlaceID: $0.originPlaceID, in: scope) }
            .compactMap { try? $0.trip() }
    }

    private var variants: [VariantRecord] {
        let here = allVariants.filter { $0.destinationPlaceID == place.id }
        guard case let .origin(id) = scope else { return here }
        return here.filter { $0.originPlaceID == id }
    }

    private var snapshotsByID: [UUID: PlanSnapshot] {
        Dictionary(
            allSnapshots.compactMap { record in
                (try? record.snapshot()).map { ($0.id, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        // Decoded once per pass (D-077). Every section below reads the
        // same drives, and reading them used to mean parsing every
        // track off disk again — a dozen times over for one screen.
        let scoped = trips
        let snapshots = snapshotsByID
        return List {
            scopeSection
            verdictSection(scoped, snapshots: snapshots)
            statsSection(scoped)
            variantsSection(scoped)
            heatmapSection(scoped)
            trendSection(scoped)
        }
        .navigationTitle(place.name)
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .task {
            // Every route here, not just the scoped ones (D-076): the
            // inventory belongs to the route, and scoping the fetch would
            // leave the other starting points' routes without counts
            // until the driver happened to switch to them.
            for variant in allVariants where variant.destinationPlaceID == place.id {
                await overpass.service.fetchInventoryIfMissing(for: variant, context: context)
            }
        }
    }

    // MARK: Which starting point (D-076)

    /// Only when there is a choice to make: most destinations are driven
    /// to from one place, and a picker with one option is furniture.
    @ViewBuilder
    private var scopeSection: some View {
        if DestinationScope.showsPicker(for: origins) {
            Section {
                Picker(selection: Binding(
                    get: { scope },
                    set: { picked = $0 }
                )) {
                    ForEach(origins) { origin in
                        Text("\(origin.name) · \(origin.drives) drive\(origin.drives == 1 ? "" : "s")")
                            .tag(DestinationScope.Selection.origin(origin.id))
                    }
                    Text(DestinationScope.allLabel).tag(DestinationScope.Selection.all)
                } label: {
                    settingsStyleLabel
                }
                .pickerStyle(.menu)
            } footer: {
                Text(DestinationScopeText.footer(
                    scope: scope,
                    destination: place.name,
                    unscopedDrives: unscopedDriveCount
                ))
            }
        }
    }

    private var settingsStyleLabel: some View {
        Label {
            Text("Drives from")
        } icon: {
            IconTile(symbol: "point.topleft.down.to.point.bottomright.curvepath.fill", color: Theme.route)
        }
    }

    // MARK: Verdict

    /// Providers with at least one plan among this destination's trips,
    /// Apple first (the default map).
    private func providersWithPlans(
        _ trips: [Trip], snapshots: [UUID: PlanSnapshot]
    ) -> [PlanSnapshot.Provider] {
        [PlanSnapshot.Provider.appleMaps, .googleRoutes].filter { provider in
            trips.contains { VerdictEngine.plan(of: $0, from: provider, snapshotsByID: snapshots) != nil }
        }
    }

    private func verdictSection(_ trips: [Trip], snapshots: [UUID: PlanSnapshot]) -> some View {
        let providers = providersWithPlans(trips, snapshots: snapshots)
        return Section("Your route vs. the plans") {
            if providers.isEmpty {
                verdictCard(
                    symbol: "hourglass",
                    color: .gray,
                    title: "No plans to compare yet",
                    detail: "Plans arrive with drives that start from the \(RootTab.route.title) screen, or when a destination is predicted at departure."
                )
            }
            ForEach(providers, id: \.self) { provider in
                providerVerdictCard(
                    VerdictEngine.verdict(forDestination: trips, snapshotsByID: snapshots, provider: provider),
                    provider: provider
                )
            }
        }
    }

    @ViewBuilder
    private func providerVerdictCard(_ verdict: VerdictEngine.Verdict, provider: PlanSnapshot.Provider) -> some View {
        let name = provider.displayName
        let confidence = "median, \(verdict.confidence.rawValue) confidence"
        switch verdict.winner {
        case .insufficientData:
            verdictCard(
                symbol: "hourglass",
                color: .gray,
                title: "Collecting data vs. \(name)",
                detail: "\(verdict.mineSampleCount)/5 of your drives, \(verdict.providerSampleCount)/5 with \(name)'s plan"
            )
        case .tie:
            verdictCard(
                symbol: "equal.circle",
                color: Theme.route,
                title: "Dead heat with \(name)",
                detail: "Within the margin (\(confidence))"
            )
        case .mine:
            verdictCard(
                symbol: "trophy.fill",
                color: Theme.win,
                title: "Your route beats \(name) by ~\(Format.duration(abs(verdict.medianDeltaSeconds)))",
                detail: confidence
            )
        case .provider:
            verdictCard(
                symbol: "map.fill",
                color: Theme.google,
                title: "\(name)'s plan wins by ~\(Format.duration(verdict.medianDeltaSeconds))",
                detail: confidence
            )
        }
    }

    private func verdictCard(symbol: String, color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, color: color, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .tintedRow(color)
    }

    // MARK: Overall stats

    private func statsSection(_ trips: [Trip]) -> some View {
        Section(scope.comparesRoutes ? "Trips from \(DestinationScope.label(for: scope, in: origins))" : "All trips here") {
            if let stats = StatsEngine.durationStats(for: trips) {
                LabeledContent("Trips", value: "\(stats.count)")
                LabeledContent("Median", value: Format.duration(stats.median))
                LabeledContent("Best", value: Format.duration(stats.best))
                LabeledContent("Worst", value: Format.duration(stats.worst))
            } else {
                Text("No trips yet.").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Your own routes, raced against each other

    private var kitVariants: [RouteVariant] {
        variants.compactMap { try? $0.variant() }
    }

    private var recordsByID: [UUID: VariantRecord] {
        Dictionary(variants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The same question asked of this moment — the driver's weekday and
    /// hour, in the zone they are standing in (D-065). Only asked inside
    /// a scope that can compare routes, so it takes the decoded variants
    /// rather than rebuilding them (D-077).
    private func recommendation(
        variants: [RouteVariant], trips: [Trip]
    ) -> RouteRecommender.Recommendation? {
        RouteRecommender.recommend(
            variants: variants,
            trips: trips,
            context: RouteRecommender.Context(now: .now, timezoneID: TimeZone.current.identifier)
        )
    }

    /// "Which of my own ways here is faster?" — answered from this
    /// destination's history (D-029), from one starting point (D-076).
    private func variantsSection(_ trips: [Trip]) -> some View {
        let kitVariants = self.kitVariants
        let race = RouteRaceEngine.race(variants: kitVariants, trips: trips)
        return Section {
            if deepLocked {
                ProLockRow(
                    title: race.routes.count >= 2
                        ? "\(race.routes.count) of your routes, raced"
                        : "Your routes, raced against each other",
                    detail: "Which of your own ways here is faster, with the signals, stop signs and turns on each — part of Pro."
                ) { showPaywall = true }
            } else if race.routes.count >= 2 {
                routesMap(race)
            }
            if !deepLocked {
                // Only within one starting point (D-076). Routes from
                // different places are different journeys, so ranking
                // them would produce a winner that means nothing.
                if scope.comparesRoutes {
                    headToHead(race)
                    let suggestion = recommendation(variants: kitVariants, trips: trips)
                    if let line = RecommendationLine.text(for: suggestion) {
                        Label(line, systemImage: "clock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if race.routes.count >= 2 {
                    Label(DestinationScopeText.noRaceAcrossOrigins, systemImage: "arrow.triangle.branch")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(Array((deepLocked ? [] : race.routes).enumerated()), id: \.element.id) { rank, route in
                if let record = recordsByID[route.id] {
                    NavigationLink {
                        VariantDetailView(variant: record)
                    } label: {
                        routeRow(route, rank: rank)
                    }
                }
            }
            if race.routes.isEmpty, !deepLocked {
                Text("No routes yet. They appear once a drive here is matched to one.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Your routes")
        } footer: {
            if race.routes.count >= 2, !deepLocked {
                Text(DestinationScopeText.routesFooter(scope: scope, destination: place.name))
            }
        }
    }

    /// Every route on one map, coloured by rank, so the difference
    /// between them is visible rather than described.
    private func routesMap(_ race: RouteRaceEngine.Race) -> some View {
        var drawn: [MapScene.DrawnRoute] = []
        for (rank, route) in race.routes.enumerated() {
            guard let record = recordsByID[route.id],
                  let polyline = Polyline.decode(record.polylineEncoded)
            else { continue }
            drawn.append(MapScene.DrawnRoute(id: route.id, polyline: polyline, rank: rank))
        }
        return MapSurfaceView(scene: MapScene(routes: drawn, showsTraffic: false, camera: .fitContent))
            .frame(height: 240)
            .listRowInsets(EdgeInsets())
    }

    @ViewBuilder
    private func headToHead(_ race: RouteRaceEngine.Race) -> some View {
        switch race.outcome {
        case .oneRouteOnly:
            if race.routes.isEmpty {
                EmptyView()
            } else {
                verdictCard(
                    symbol: "arrow.triangle.branch",
                    color: .gray,
                    title: "Only one way so far",
                    detail: "Drive here another way and Route Rebel will race the two."
                )
            }
        case let .collecting(drivesNeeded):
            verdictCard(
                symbol: "hourglass",
                color: .gray,
                title: "Too early to call it",
                detail: "\(drivesNeeded) more drive\(drivesNeeded == 1 ? "" : "s") on the thinner route"
            )
        case let .tie(gapSeconds):
            verdictCard(
                symbol: "equal.circle",
                color: Theme.route,
                title: "Dead heat",
                detail: "\(Format.duration(gapSeconds)) apart \(sampleLine(race))"
            )
        case let .winner(gapSeconds, confidence):
            verdictCard(
                symbol: "trophy.fill",
                color: Theme.win,
                title: "\(race.fastest?.name ?? "One route") beats \(race.runnerUp?.name ?? "the other") by \(Format.duration(gapSeconds))",
                detail: "median \(sampleLine(race)) · \(confidence.rawValue) confidence"
            )
        }
    }

    /// "across 4 and 5 drives" — how much history the call rests on.
    private func sampleLine(_ race: RouteRaceEngine.Race) -> String {
        guard let fastest = race.fastest, let runnerUp = race.runnerUp else { return "" }
        return "across \(fastest.stats.count) and \(runnerUp.stats.count) drives"
    }

    /// Where a route starts, for the row (D-075).
    private func originCaption(_ route: RouteRaceEngine.Route) -> String? {
        RouteOrigin.caption(of: recordsByID[route.id]?.originPlaceID, in: allPlaces)
    }

    private func routeRow(_ route: RouteRaceEngine.Route, rank: Int) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.routeColor(rank: rank))
                .frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(route.name)
                        .font(.headline)
                    // Beside the name rather than in the caption below:
                    // it is the thing that tells two routes apart, and
                    // the caption is already three facts long.
                    if let origin = originCaption(route) {
                        Text(origin)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(Format.duration(route.stats.median))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(rank == 0 ? Theme.win : .secondary)
                }
                HStack(spacing: 8) {
                    Text("\(route.stats.count) drive\(route.stats.count == 1 ? "" : "s")")
                    if let signals = route.signalCount, let stops = route.stopSignCount {
                        Text("· \(signals) signals, \(stops) stop signs")
                    }
                    if let turns = route.turns {
                        Text("· \(TurnText.lefts(turns))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Heatmap

    private func heatmapSection(_ trips: [Trip]) -> some View {
        Section {
            ProLock(locked: deepLocked, title: "Your best hours — Pro", onUnlock: { showPaywall = true }) {
                heatmapBody(trips)
            }
        } header: {
            Text("By day and time (median)")
        } footer: {
            Text("Minutes. Green is your fastest slot, orange the slowest.")
        }
    }

    @ViewBuilder
    private func heatmapBody(_ trips: [Trip]) -> some View {
            let matrix = StatsEngine.weekdayBucketMatrix(for: trips)
            if matrix.isEmpty {
                Text("Not enough trips yet.").foregroundStyle(.secondary)
            } else {
                let medians = matrix.values.map(\.median)
                let best = medians.min() ?? 0
                let worst = medians.max() ?? 1
                Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                    GridRow {
                        Text("")
                        ForEach(["12a", "4a", "8a", "12p", "4p", "8p"], id: \.self) {
                            Text($0).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(1...7, id: \.self) { weekday in
                        GridRow {
                            Text(["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][weekday])
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                            ForEach(0..<6, id: \.self) { bucket in
                                heatCell(
                                    matrix[.init(weekday: weekday, bucket: bucket)],
                                    best: best,
                                    worst: worst
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
    }

    private func heatCell(_ stats: StatsEngine.DurationStats?, best: Double, worst: Double) -> some View {
        let color: Color
        if let stats {
            let span = max(1, worst - best)
            let heat = (stats.median - best) / span // 0 = fastest, 1 = slowest
            // Green through amber to orange — the trip-row palette, not a
            // stoplight red; the slowest slot is a fact, not an alarm.
            color = Color(hue: 0.36 - 0.28 * heat, saturation: 0.55, brightness: 0.88)
        } else {
            color = Color.secondary.opacity(0.12)
        }
        return RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(height: 22)
            .overlay {
                if let stats {
                    Text("\(Int(stats.median / 60))")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.black.opacity(0.7))
                }
            }
    }

    // MARK: Trend

    private func trendSection(_ trips: [Trip]) -> some View {
        Section("Month over month (median)") {
            ProLock(locked: deepLocked, title: "Month over month — Pro", onUnlock: { showPaywall = true }) {
                trendBody(trips)
            }
        }
    }

    @ViewBuilder
    private func trendBody(_ trips: [Trip]) -> some View {
            let trend = StatsEngine.monthlyTrend(for: trips)
            if trend.count < 2 {
                Text("Trends appear after a second month of driving.")
                    .foregroundStyle(.secondary)
            } else {
                Chart(trend, id: \.month) { entry in
                    BarMark(
                        x: .value("Month", entry.month),
                        y: .value("Median minutes", entry.stats.median / 60)
                    )
                    .foregroundStyle(Theme.route.gradient)
                    .cornerRadius(4)
                }
                .frame(height: 160)
                .padding(.vertical, 4)
            }
    }
}

/// @State needs a stable identity for the non-Observable service.
@MainActor
final class OverpassServiceHolder {
    let service = OverpassService()
}
