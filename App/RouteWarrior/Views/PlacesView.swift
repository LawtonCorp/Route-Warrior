import CoreLocation
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
        let kind = Place.Kind(stored: place.kindRaw)
        return HStack(spacing: 12) {
            IconTile(symbol: kind.symbol, color: kind.color, size: 34)
            VStack(alignment: .leading) {
                Text(place.name).font(.headline)
                Text(place.address.isEmpty
                     ? kind.rawValue.capitalized
                     : "\(kind.rawValue.capitalized) · \(place.address)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct PlaceEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var locationService
    @State private var name = ""
    @State private var kind: Place.Kind = .custom
    @State private var addressQuery = ""
    @State private var match: AddressMatch?
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var focus: PlaceMapFocus?
    @State private var completer = AddressCompleter()
    @State private var resolving = false
    @State private var lookupFailed = false
    @State private var cameraSettled = false

    /// City scale: about 12 km across — the neighbourhood and its main
    /// roads, no pinching needed (D-021).
    private static let citySpanMeters: Double = 12_000
    /// After an address match: close enough to check the pin is on the
    /// right building.
    private static let pinSpanMeters: Double = 1_500

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $kind) {
                        ForEach(Place.Kind.allCases, id: \.self) { kind in
                            Text(kind.rawValue.capitalized).tag(kind)
                        }
                    }
                }
                Section {
                    TextField("Search an address or place", text: $addressQuery)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { resolve(addressQuery) }
                    ForEach(completer.suggestions) { suggestion in
                        Button {
                            resolve(suggestion.query, title: suggestion.title)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                    if resolving {
                        ProgressView()
                    }
                } header: {
                    Text("Address")
                } footer: {
                    if lookupFailed {
                        Text("No match — try a fuller address, or tap the map.")
                    } else if let match {
                        Text(match.address)
                    }
                }
                Section("Location — or tap the map") {
                    PlacePickerMap(
                        focus: focus,
                        coordinate: coordinate,
                        markerTitle: name.isEmpty ? "Place" : name
                    ) { tapped in
                        coordinate = tapped
                        // A hand-placed pin has no verified address.
                        match = nil
                        lookupFailed = false
                    }
                    .frame(height: 280)
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
            .onAppear { settleCamera() }
            .onChange(of: locationService.lastKnownCoordinate == nil) { settleCamera() }
            .onChange(of: addressQuery) { _, newValue in
                lookupFailed = false
                // The resolved address is written back into the field;
                // don't re-suggest it.
                guard newValue != match?.address else { return }
                completer.update(query: newValue)
            }
        }
    }

    /// Open at city scale around the user as soon as a fix exists, and
    /// ask for one if none has arrived yet.
    @MainActor
    private func settleCamera() {
        guard !cameraSettled else { return }
        if let here = locationService.lastKnownCoordinate {
            focus = PlaceMapFocus(center: here, spanMeters: Self.citySpanMeters)
            completer.focus(on: here)
            cameraSettled = true
        } else {
            locationService.requestOneShotLocation()
        }
    }

    @MainActor
    private func resolve(_ text: String, title: String? = nil) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !resolving else { return }
        resolving = true
        lookupFailed = false
        let near = locationService.lastKnownCoordinate
        Task {
            let found = await AddressCompleter.resolve(query, near: near)
            resolving = false
            guard let found else {
                lookupFailed = true
                return
            }
            match = found
            coordinate = CLLocationCoordinate2D(
                latitude: found.coordinate.latitude,
                longitude: found.coordinate.longitude
            )
            focus = PlaceMapFocus(center: found.coordinate, spanMeters: Self.pinSpanMeters)
            cameraSettled = true
            if name.isEmpty { name = title ?? found.name }
            addressQuery = found.address
            completer.update(query: "")
        }
    }

    private func save() {
        guard let coordinate else { return }
        let place = Place(
            name: name,
            coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
            kind: kind,
            address: match?.address ?? ""
        )
        context.insert(PlaceRecord(place))
        try? context.save()
        dismiss()
    }
}
