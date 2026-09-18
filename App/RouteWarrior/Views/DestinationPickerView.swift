import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import SwiftUI

/// Where the departure notification lands when it is tapped rather than
/// pulled down (D-082).
///
/// The notification carries the same four places as buttons, but the
/// buttons are behind a long press that a driver at a junction will not
/// find. A tap used to do nothing at all. It now opens this: the same
/// question, on a screen, with every saved place rather than the four
/// that fit on a notification.
struct DestinationPickerView: View {
    @Environment(RecordingPipeline.self) private var pipeline
    @Environment(\.dismiss) private var dismiss
    @Query(sort: PlaceOrder.descriptors) private var places: [PlaceRecord]

    var body: some View {
        NavigationStack {
            List {
                if places.isEmpty {
                    ContentUnavailableView(
                        "No saved places yet",
                        systemImage: "mappin.slash",
                        description: Text(
                            "Save the places you drive to on the Places tab, and Route Rebel can name this drive and compare it against the plans."
                        )
                    )
                } else {
                    Section {
                        ForEach(places) { place in
                            Button {
                                pipeline.requestSnapshot(to: place.id)
                                dismiss()
                            } label: {
                                row(place)
                            }
                            .tint(.primary)
                        }
                    } footer: {
                        Text("Naming the drive gets you the comparison against Google's and Apple's plans, and files it under this place in your history.")
                    }
                }
            }
            .navigationTitle("Where are you headed?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Not "Cancel": the drive carries on either way, and
                    // a driver who does not want to answer should not be
                    // told they cancelled their own recording.
                    Button("Not now") {
                        pipeline.dismissDestinationPicker()
                        dismiss()
                    }
                }
            }
        }
    }

    private func row(_ place: PlaceRecord) -> some View {
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
