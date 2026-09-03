import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import SwiftUI

/// One of the driver's own routes to a destination: what it is called,
/// how it has performed, what it costs in signals and stop signs, and
/// every drive that took it (D-029).
struct VariantDetailView: View {
    @Environment(\.modelContext) private var context
    let variant: VariantRecord
    @Query(sort: \TripRecord.startedAt, order: .reverse) private var allTrips: [TripRecord]
    @Query private var allSnapshots: [SnapshotRecord]
    @State private var draftName = ""

    private var records: [TripRecord] {
        allTrips.filter { $0.variantID == variant.id }
    }

    private var trips: [Trip] {
        records.compactMap { try? $0.trip() }
    }

    private var polyline: Polyline? {
        Polyline.decode(variant.polylineEncoded)
    }

    private var title: String {
        (try? variant.variant())?.displayName ?? "Route"
    }

    var body: some View {
        List {
            nameSection
            if let polyline {
                Section {
                    MapSurfaceView(scene: MapScene(
                        routes: [MapScene.DrawnRoute(id: variant.id, polyline: polyline, rank: 0)],
                        showsTraffic: false,
                        camera: .fitContent
                    ))
                    .frame(height: 240)
                    .listRowInsets(EdgeInsets())
                }
            }
            statsSection
            intersectionsSection
            tripsSection
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draftName = variant.customName }
        .onDisappear { commitName() }
    }

    /// The generated name says which street; the driver's name says which
    /// idea. Renaming keeps both — the generated one stays the
    /// placeholder, so clearing the field restores it.
    private var nameSection: some View {
        Section {
            TextField(variant.autoName.isEmpty ? "Name this route" : variant.autoName, text: $draftName)
                .submitLabel(.done)
                .onSubmit { commitName() }
        } header: {
            Text("Name")
        } footer: {
            Text("Call it what you call it — \"the back way\" beats \"via Maple Ave\" when you are choosing.")
        }
    }

    private var statsSection: some View {
        Section("This route") {
            if let stats = StatsEngine.durationStats(for: trips) {
                LabeledContent("Drives", value: "\(stats.count)")
                LabeledContent("Median", value: Format.duration(stats.median))
                LabeledContent("Best", value: Format.duration(stats.best))
                LabeledContent("Worst", value: Format.duration(stats.worst))
            } else {
                Text("No counted drives yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var intersectionsSection: some View {
        Section {
            if let signals = variant.signalCount, let stops = variant.stopSignCount {
                LabeledContent("Signals") {
                    Label("\(signals)", systemImage: "circle.fill")
                        .foregroundStyle(Theme.armed)
                }
                LabeledContent("Stop signs") {
                    Label("\(stops)", systemImage: "octagon.fill")
                        .foregroundStyle(Theme.recording)
                }
                if let coverage = variant.coverageRaw {
                    LabeledContent("Map coverage", value: coverage)
                }
            } else {
                Text("Counting signals and stop signs…")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("What it costs you")
        } footer: {
            Text("Counted from OpenStreetMap along this route. More intersections explain a slower median more often than distance does.")
        }
    }

    private var tripsSection: some View {
        Section("Drives on this route") {
            if records.isEmpty {
                Text("None yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(records) { record in
                NavigationLink {
                    TripDetailView(record: record)
                } label: {
                    TripRowView(record: record, deltaSeconds: record.etaDeltaSeconds(in: allSnapshots))
                }
            }
        }
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != variant.customName else { return }
        variant.customName = trimmed
        try? context.save()
    }
}
