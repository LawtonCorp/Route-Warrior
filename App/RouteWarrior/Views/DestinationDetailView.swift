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

    private var verdictSection: some View {
        Section("Your route vs. Google") {
            let verdict = VerdictEngine.verdict(forDestination: trips, snapshotsByID: snapshotsByID)
            switch verdict.winner {
            case .insufficientData:
                Label(
                    "Collecting data (\(verdict.mineSampleCount)/5 yours, \(verdict.googleSampleCount)/5 Google)",
                    systemImage: "hourglass"
                )
                .foregroundStyle(.secondary)
            case .tie:
                Label("Dead heat — within the margin", systemImage: "equal.circle")
            case .mine:
                Label(
                    "Your route wins by ~\(Format.duration(abs(verdict.medianDeltaSeconds))) (median, \(verdict.confidence.rawValue) confidence)",
                    systemImage: "trophy.fill"
                )
                .foregroundStyle(.green)
            case .google:
                Label(
                    "Google's plan wins by ~\(Format.duration(verdict.medianDeltaSeconds)) (median, \(verdict.confidence.rawValue) confidence)",
                    systemImage: "map.fill"
                )
                .foregroundStyle(.orange)
            }
        }
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

    // MARK: Variants

    private var variantsSection: some View {
        Section("Routes") {
            ForEach(variants) { variant in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(variant.autoName.isEmpty ? "Route" : variant.autoName)
                            .font(.headline)
                        Spacer()
                        if let stats = StatsEngine.durationStats(
                            for: trips.filter { $0.variantID == variant.id }
                        ) {
                            Text("median \(Format.duration(stats.median))")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    intersectionLine(for: variant)
                }
            }
        }
    }

    private func intersectionLine(for variant: VariantRecord) -> some View {
        HStack(spacing: 6) {
            if let signals = variant.signalCount, let stops = variant.stopSignCount {
                Text("\(signals) signals · \(stops) stop signs on this route")
                if let coverage = variant.coverageRaw {
                    Text("(map coverage: \(coverage))")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Counting signals and stop signs…")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    // MARK: Heatmap

    private var heatmapSection: some View {
        Section("By day and time (median)") {
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
    }

    private func heatCell(_ stats: StatsEngine.DurationStats?, best: Double, worst: Double) -> some View {
        let color: Color
        if let stats {
            let span = max(1, worst - best)
            let heat = (stats.median - best) / span // 0 = fastest, 1 = slowest
            color = Color(hue: 0.33 - 0.33 * heat, saturation: 0.7, brightness: 0.85)
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
