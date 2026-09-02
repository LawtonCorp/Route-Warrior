import RouteWarriorStore
import SwiftData
import SwiftUI

struct TripsView: View {
    @Environment(StoreService.self) private var store
    @Query(sort: \TripRecord.startedAt, order: .reverse) private var trips: [TripRecord]
    @Query private var places: [PlaceRecord]
    @Query private var snapshots: [SnapshotRecord]
    @State private var destinationFilter: UUID?
    @State private var showPaywall = false

    private var gated: (visible: [TripRecord], hiddenCount: Int) {
        HistoryGate.visible(trips, tier: store.tier)
    }

    private var filtered: [TripRecord] {
        guard let destinationFilter else { return gated.visible }
        return gated.visible.filter { $0.destinationPlaceID == destinationFilter }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { record in
                    NavigationLink {
                        TripDetailView(record: record)
                    } label: {
                        TripRowView(
                            record: record,
                            deltaSeconds: record.etaDeltaSeconds(in: snapshots)
                        )
                    }
                }
                if gated.hiddenCount > 0 {
                    Button {
                        showPaywall = true
                    } label: {
                        Label {
                            Text("\(gated.hiddenCount) older trips — unlock with Pro")
                        } icon: {
                            IconTile(symbol: "lock.fill", color: Theme.pro)
                        }
                    }
                    .tint(.primary)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No trips recorded",
                        systemImage: "car",
                        description: Text("Drive somewhere — Route Warrior records automatically.")
                    )
                }
            }
            .navigationTitle("Trips")
            .toolbar {
                Menu {
                    Button("All destinations") { destinationFilter = nil }
                    ForEach(places) { place in
                        Button(place.name) { destinationFilter = place.id }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }
}
