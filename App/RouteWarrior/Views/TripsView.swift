import RouteWarriorStore
import SwiftData
import SwiftUI

/// Every recorded trip, today's first (D-026). Sorting and filtering run
/// through `TripOrganizer`, so what this screen shows is decided by tested
/// code rather than by the view.
struct TripsView: View {
    @Environment(StoreService.self) private var store
    @Query(sort: \TripRecord.startedAt, order: .reverse) private var trips: [TripRecord]
    @Query(sort: \PlaceRecord.createdAt) private var places: [PlaceRecord]
    @Query private var snapshots: [SnapshotRecord]
    @State private var sort: TripSort = .newest
    @State private var destinationFilter: UUID?
    @State private var outcome: TripOutcome = .any
    @State private var showPaywall = false

    private var gated: (visible: [TripRecord], hiddenCount: Int) {
        HistoryGate.visible(trips, tier: store.tier)
    }

    private var arranged: (today: [TripRecord], earlier: [TripRecord]) {
        TripOrganizer(sort: sort, destination: destinationFilter, outcome: outcome)
            .arrange(gated.visible, delta: { $0.etaDeltaSeconds(in: snapshots) })
    }

    private var isFiltered: Bool { destinationFilter != nil || outcome != .any }

    var body: some View {
        NavigationStack {
            List {
                let sections = arranged
                if !sections.today.isEmpty {
                    Section("Today") {
                        ForEach(sections.today) { row($0) }
                    }
                }
                if !sections.earlier.isEmpty {
                    Section(sections.today.isEmpty ? "All trips" : "Earlier") {
                        ForEach(sections.earlier) { row($0) }
                    }
                }
                if gated.hiddenCount > 0 {
                    Section {
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
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .overlay {
                let sections = arranged
                if sections.today.isEmpty, sections.earlier.isEmpty {
                    emptyState
                }
            }
            .navigationTitle("Trips")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { sortMenu }
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
        }
    }

    private func row(_ record: TripRecord) -> some View {
        NavigationLink {
            TripDetailView(record: record)
        } label: {
            TripRowView(record: record, deltaSeconds: record.etaDeltaSeconds(in: snapshots))
        }
    }

    private var emptyState: some View {
        Group {
            if isFiltered {
                ContentUnavailableView(
                    "No trips match",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Clear the filter to see the rest of your trips.")
                )
            } else {
                ContentUnavailableView(
                    "No trips recorded",
                    systemImage: "car",
                    description: Text("Drive somewhere — Route Rebel records automatically.")
                )
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(TripSort.allCases) { option in
                    Label(option.label, systemImage: option.symbol).tag(option)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Outcome", selection: $outcome) {
                ForEach(TripOutcome.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            Picker("Destination", selection: $destinationFilter) {
                Text("All destinations").tag(UUID?.none)
                ForEach(places) { place in
                    Text(place.name).tag(UUID?.some(place.id))
                }
            }
        } label: {
            Label("Filter", systemImage: isFiltered
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }
}

/// One trip in a list: how it went against the ETA, at a glance.
struct TripRowView: View {
    let record: TripRecord
    /// Actual duration minus the provider's ETA (see
    /// `TripRecord.etaDeltaSeconds`); nil when the trip has no comparison.
    var deltaSeconds: Double? = nil

    private var tone: TripTone {
        .forTrip(deltaSeconds: deltaSeconds, excluded: record.excludedFromStats)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tone.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tone.color)
                .frame(width: 32, height: 32)
                .background(tone.color.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(record.startedAt, format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
                        .font(.subheadline)
                    Spacer()
                    Text(Format.duration(record.endedAt.timeIntervalSince(record.startedAt)))
                        .font(.subheadline.monospacedDigit())
                }
                HStack(spacing: 8) {
                    Text(Format.distance(record.distanceM))
                    if record.excludedFromStats {
                        Text("excluded")
                    }
                    if let deltaSeconds {
                        Text("\(Format.signedDelta(deltaSeconds)) vs. ETA")
                            .foregroundStyle(tone.color)
                            .monospacedDigit()
                    } else if record.snapshotID == nil {
                        Text("no comparison")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// `TripRecord` already carries everything the organizer sorts on.
extension TripRecord: TripSortable {}
