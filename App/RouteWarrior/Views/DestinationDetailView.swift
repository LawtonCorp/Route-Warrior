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
    let place: PlaceRecord
    @State private var overpass = OverpassServiceHolder()

    @Query private var allTrips: [TripRecord]
    @Query private var allVariants: [VariantRecord]
    @Query private var allSnapshots: [SnapshotRecord]

    private var trips: [Trip] {
        allTrips
            .filter { $0.destinationPlaceID == place.id }
            .compactMap { try? $0.trip() }
    }

    private var variants: [VariantRecord] {
        allVariants.filter { $0.destinationPlaceID == place.id }
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
        List {
            verdictSection
            statsSection
            variantsSection
            heatmapSection
            trendSection
        }
        .navigationTitle(place.name)
        .task {
            for variant in variants {
                await overpass.service.fetchInventoryIfMissing(for: variant, context: context)
            }
        }
    }

    // MARK: Verdict

    /// Providers with at least one plan among this destination's trips,
    /// Apple first (the default map).
    private var providersWithPlans: [PlanSnapshot.Provider] {
        [PlanSnapshot.Provider.appleMaps, .googleRoutes].filter { provider in
            trips.contains { VerdictEngine.plan(of: $0, from: provider, snapshotsByID: snapshotsByID) != nil }
        }
    }

    private var verdictSection: some View {
        Section("Your route vs. the plans") {
            if providersWithPlans.isEmpty {
                verdictCard(
                    symbol: "hourglass",
                    color: .gray,
                    title: "No plans to compare yet",
                    detail: "Plans arrive with drives that start from the Plan screen, or when a destination is predicted at departure."
                )
            }
            ForEach(providersWithPlans, id: \.self) { provider in
                providerVerdictCard(
                    VerdictEngine.verdict(forDestination: trips, snapshotsByID: snapshotsByID, provider: provider),
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

    private var statsSection: some View {
        Section("All trips here") {
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

    /// "Which of my own ways here is faster?" — answered from this
    /// destination's history (D-029).
    private var race: RouteRaceEngine.Race {
        RouteRaceEngine.race(variants: kitVariants, trips: trips)
    }

    private var variantsSection: some View {
        let race = self.race
        return Section {
            if race.routes.count >= 2 {
                routesMap(race)
            }
            headToHead(race)
            ForEach(Array(race.routes.enumerated()), id: \.element.id) { rank, route in
                if let record = recordsByID[route.id] {
                    NavigationLink {
                        VariantDetailView(variant: record)
                    } label: {
                        routeRow(route, rank: rank)
                    }
                }
            }
            if race.routes.isEmpty {
                Text("No routes yet. They appear once a drive here is matched to one.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Your routes")
        } footer: {
            if race.routes.count >= 2 {
                Text("Each route is coloured to match its line on the map. Tap one to name it and see its drives.")
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

    private func routeRow(_ route: RouteRaceEngine.Route, rank: Int) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.routeColor(rank: rank))
                .frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(route.name)
                        .font(.headline)
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
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Heatmap

    private var heatmapSection: some View {
        Section {
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
        } header: {
            Text("By day and time (median)")
        } footer: {
            Text("Minutes. Green is your fastest slot, orange the slowest.")
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

    private var trendSection: some View {
        Section("Month over month (median)") {
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
}

/// @State needs a stable identity for the non-Observable service.
@MainActor
final class OverpassServiceHolder {
    let service = OverpassService()
}
