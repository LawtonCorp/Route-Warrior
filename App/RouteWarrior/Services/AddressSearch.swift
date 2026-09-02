import Foundation
import MapKit
import RouteWarriorKit

/// A resolved address, in kit terms.
struct AddressMatch: Sendable, Equatable {
    var name: String
    var address: String
    var coordinate: Coordinate
}

/// One autocomplete row. Top-level on purpose: it is built inside the
/// completer's off-main delegate callback, so it must not inherit the
/// completer's main-actor isolation.
struct AddressSuggestion: Identifiable, Sendable, Equatable {
    let title: String
    let subtitle: String
    var id: String { title + "|" + subtitle }
    /// What to look up when the row is tapped.
    var query: String { subtitle.isEmpty ? title : "\(title), \(subtitle)" }
}

/// Address autocomplete and lookup over Apple's MapKit search: no key, no
/// cost, and nothing leaves the phone except the query Apple needs to
/// answer (D-021). The completer's delegate calls arrive off the main
/// actor, so only value copies of its results cross back.
@MainActor
@Observable
final class AddressCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var suggestions: [AddressSuggestion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        if query.isEmpty {
            suggestions = []
        }
        completer.queryFragment = query
    }

    /// Bias suggestions toward where the user is.
    func focus(on center: Coordinate) {
        completer.region = Self.region(around: center)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let items = completer.results.prefix(6).map {
            AddressSuggestion(title: $0.title, subtitle: $0.subtitle)
        }
        Task { @MainActor [weak self] in
            self?.suggestions = Array(items)
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in
            self?.suggestions = []
        }
    }

    /// Resolve free text (a tapped suggestion or a typed address) to one
    /// coordinate. The MapKit objects never leave the completion handler;
    /// only Sendable values come back.
    nonisolated static func resolve(_ text: String, near center: Coordinate?) async -> AddressMatch? {
        await withCheckedContinuation { continuation in
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            if let center {
                request.region = region(around: center)
            }
            MKLocalSearch(request: request).start { response, _ in
                guard let item = response?.mapItems.first else {
                    continuation.resume(returning: nil)
                    return
                }
                let location = item.placemark.coordinate
                continuation.resume(returning: AddressMatch(
                    name: item.name ?? text,
                    address: item.placemark.title ?? text,
                    coordinate: Coordinate(latitude: location.latitude, longitude: location.longitude)
                ))
            }
        }
    }

    private nonisolated static func region(around center: Coordinate) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
            latitudinalMeters: 50_000,
            longitudinalMeters: 50_000
        )
    }
}
