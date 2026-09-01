import CoreLocation
import MapKit
import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import SwiftUI

struct PlacesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PlaceRecord.createdAt) private var places: [PlaceRecord]
    @State private var editingNew = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(places) { place in
                    NavigationLink {
                        DestinationDetailView(place: place)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(place.name).font(.headline)
                            Text(kindLabel(place.kindRaw))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
        }
    }

    private func kindLabel(_ raw: String) -> String {
        Place.Kind(rawValue: raw)?.rawValue.capitalized ?? "Custom"
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
