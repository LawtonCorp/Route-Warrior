import CoreLocation
import MapKit
import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import SwiftUI

struct PlacesView: View {
    @Environment(\.modelContext) private var context
    @Environment(StoreService.self) private var store
    @Query(sort: \PlaceRecord.createdAt) private var places: [PlaceRecord]
    @State private var editingNew = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(places.enumerated()), id: \.element.id) { rank, place in
                    if store.policy.canAnalyzeDestination(atRank: rank, tier: store.tier) {
                        NavigationLink {
                            DestinationDetailView(place: place)
                        } label: {
                            placeRow(place)
                        }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                placeRow(place)
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(Theme.pro)
                            }
                        }
                        .tint(.primary)
                    }
                }
                .onDelete { offsets in
                    for offset in offsets {
                        context.delete(places[offset])
                    }
                    try? context.save()
                }
            }
            .overlay {
                if places.isEmpty {
                    ContentUnavailableView(
                        "No saved places",
                        systemImage: "mappin.and.ellipse",
                        description: Text("Save home, work, and school so trips get matched to destinations.")
                    )
                }
            }
            .navigationTitle("Places")
            .toolbar {
                Button {
                    editingNew = true
                } label: {
                    Label("Add place", systemImage: "plus")
                }
            }
            .sheet(isPresented: $editingNew) {
                PlaceEditView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    private func placeRow(_ place: PlaceRecord) -> some View {
        let kind = Place.Kind(rawValue: place.kindRaw) ?? .custom
        return HStack(spacing: 12) {
            IconTile(symbol: kind.symbol, color: kind.color, size: 34)
            VStack(alignment: .leading) {
                Text(place.name).font(.headline)
                Text(kind.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PlaceEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: Place.Kind = .custom
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Type", selection: $kind) {
                    ForEach(Place.Kind.allCases, id: \.self) { kind in
                        Text(kind.rawValue.capitalized).tag(kind)
                    }
                }
                Section("Location — tap the map") {
                    MapReader { proxy in
                        Map(position: $camera) {
                            if let coordinate {
                                Marker(name.isEmpty ? "Place" : name, coordinate: coordinate)
                            }
                            UserAnnotation()
                        }
                        .frame(height: 280)
                        .onTapGesture { screenPoint in
                            coordinate = proxy.convert(screenPoint, from: .local)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("New place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty || coordinate == nil)
                }
            }
        }
    }

    private func save() {
        guard let coordinate else { return }
        let place = Place(
            name: name,
            coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
            kind: kind
        )
        context.insert(PlaceRecord(place))
        try? context.save()
        dismiss()
    }
}
