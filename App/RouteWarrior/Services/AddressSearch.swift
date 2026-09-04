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
    /// Known when the row came from a place lookup rather than the
    /// completer (D-040); a tap then goes straight there.
    var coordinate: Coordinate?
    /// From the driver to the place, when both are known.
    var distanceMeters: Double?

    init(title: String, subtitle: String, coordinate: Coordinate? = nil, distanceMeters: Double? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.coordinate = coordinate
        self.distanceMeters = distanceMeters
    }

    /// Two branches of one chain differ by where they are, so the
    /// coordinate is part of the identity when there is one.
    var id: String {
        guard let coordinate else { return title + "|" + subtitle }
        return title + "|" + subtitle + "|"
            + String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
    }

    /// What to look up when the row is tapped and no coordinate is known.
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
    /// What the completer last answered, before any detail was merged in.
    private var completions: [AddressSuggestion] = []
    /// Places found for a bare business name, keyed by that name (D-040).
    private var details: [String: [AddressSuggestion]] = [:]
    private var lookupsInFlight: Set<String> = []
    private var focusCenter: Coordinate?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        if query.isEmpty {
            completions = []
            suggestions = []
            details = [:]
        }
        completer.queryFragment = query
    }

    /// Bias suggestions toward where the user is.
    func focus(on center: Coordinate) {
        focusCenter = center
        completer.region = Self.region(around: center)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let items = completer.results.prefix(6).map {
            AddressSuggestion(title: $0.title, subtitle: $0.subtitle)
        }
        Task { @MainActor [weak self] in
            self?.publish(completions: Array(items))
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in
            self?.publish(completions: [])
        }
    }

    private func publish(completions: [AddressSuggestion]) {
        self.completions = completions
        suggestions = SuggestionDetail.merge(completions: completions, details: details)
        for name in SuggestionDetail.namesNeedingDetail(in: completions)
        where details[name] == nil && !lookupsInFlight.contains(name) {
            lookupsInFlight.insert(name)
            let near = focusCenter
            Task { [weak self] in
                let found = await Self.places(named: name, near: near)
                self?.record(found, for: name)
            }
        }
    }

    private func record(_ found: [AddressSuggestion], for name: String) {
        lookupsInFlight.remove(name)
        details[name] = found
        // The driver may have typed on since; only a list still naming
        // this business gets rebuilt.
        guard completions.contains(where: { $0.title == name }) else { return }
        suggestions = SuggestionDetail.merge(completions: completions, details: details)
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

    /// The locations of one business near the driver, nearest first, each
    /// with an address a driver can recognise. Bare chain names from the
    /// completer are answered this way (D-040).
    nonisolated static func places(named name: String, near center: Coordinate?) async -> [AddressSuggestion] {
        await withCheckedContinuation { continuation in
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = name
            request.resultTypes = .pointOfInterest
            if let center {
                request.region = region(around: center)
            }
            MKLocalSearch(request: request).start { response, _ in
                let found = (response?.mapItems ?? []).map { item -> AddressSuggestion in
                    let location = item.placemark.coordinate
                    let coordinate = Coordinate(latitude: location.latitude, longitude: location.longitude)
                    return AddressSuggestion(
                        title: item.name ?? name,
                        subtitle: shortAddress(of: item.placemark),
                        coordinate: coordinate,
                        distanceMeters: center.map { Geo.distanceMeters(from: $0, to: coordinate) }
                    )
                }
                continuation.resume(returning: SuggestionDetail.nearest(found))
            }
        }
    }

    /// "1234 Main St, Boulder" — enough to tell branches apart, short
    /// enough for one line.
    private nonisolated static func shortAddress(of placemark: MKPlacemark) -> String {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }.joined(separator: " ")
        let parts = [street, placemark.locality ?? ""].filter { !$0.isEmpty }
        if parts.isEmpty { return placemark.title ?? "" }
        return parts.joined(separator: ", ")
    }

    private nonisolated static func region(around center: Coordinate) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
            latitudinalMeters: 50_000,
            longitudinalMeters: 50_000
        )
    }
}
