import CoreLocation
import GoogleMaps
import MapKit
import RouteWarriorKit
import SwiftUI
import UIKit

/// Where a place-picker map should look, in provider-neutral terms: a
/// centre and how wide a slice of the world to show. Each surface turns
/// this into its own camera, so the New Place screen never names a
/// provider (D-024).
struct PlaceMapFocus: Equatable {
    var center: Coordinate
    /// The full width and height of the visible square, in metres.
    var spanMeters: Double

    /// Metres per degree of latitude, the same spherical constant
    /// MapKit's `latitudinalMeters` uses.
    private static let metersPerDegreeLatitude: Double = 111_320

    /// The south-west and north-east corners of that square. Pure
    /// geometry, so it is testable with no map view in sight.
    var corners: (southWest: Coordinate, northEast: Coordinate) {
        let halfLat = spanMeters / 2 / Self.metersPerDegreeLatitude
        // A degree of longitude shrinks towards the poles; the floor
        // keeps the divisor away from zero at the top of the world.
        let shrink = max(0.01, cos(center.latitude * .pi / 180))
        let halfLon = spanMeters / 2 / (Self.metersPerDegreeLatitude * shrink)
        return (
            Coordinate(latitude: center.latitude - halfLat, longitude: center.longitude - halfLon),
            Coordinate(latitude: center.latitude + halfLat, longitude: center.longitude + halfLon)
        )
    }
}

/// The map on the New Place screen, drawn on whichever surface the user
/// chose (FR-19). Tapping the map reports a coordinate; the caller owns
/// the pin.
struct PlacePickerMap: View {
    @Environment(MapSettings.self) private var mapSettings
    var focus: PlaceMapFocus?
    var coordinate: CLLocationCoordinate2D?
    var markerTitle: String
    var onPick: (CLLocationCoordinate2D) -> Void

    var body: some View {
        switch mapSettings.provider {
        case .apple:
            ApplePlacePicker(
                focus: focus, coordinate: coordinate, markerTitle: markerTitle, onPick: onPick
            )
        case .google:
            GooglePlacePicker(
                focus: focus, coordinate: coordinate, markerTitle: markerTitle, onPick: onPick
            )
        }
    }
}

/// Apple's picker: the v1 behaviour, now driven by a shared focus.
struct ApplePlacePicker: View {
    var focus: PlaceMapFocus?
    var coordinate: CLLocationCoordinate2D?
    var markerTitle: String
    var onPick: (CLLocationCoordinate2D) -> Void

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let coordinate {
                    Marker(markerTitle, coordinate: coordinate)
                }
                UserAnnotation()
            }
            .onTapGesture { screenPoint in
                if let tapped = proxy.convert(screenPoint, from: .local) {
                    onPick(tapped)
                }
            }
        }
        .onAppear { apply(focus) }
        .onChange(of: focus) { _, newFocus in apply(newFocus) }
    }

    private func apply(_ focus: PlaceMapFocus?) {
        guard let focus else { return }
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: focus.center.latitude, longitude: focus.center.longitude
            ),
            latitudinalMeters: focus.spanMeters,
            longitudinalMeters: focus.spanMeters
        ))
    }
}

/// Google's picker through the Maps SDK for iOS. The SDK draws its own
/// logo and attribution; nothing here covers them.
struct GooglePlacePicker: UIViewRepresentable {
    var focus: PlaceMapFocus?
    var coordinate: CLLocationCoordinate2D?
    var markerTitle: String
    var onPick: (CLLocationCoordinate2D) -> Void

    /// Holds the pin and the last camera it framed, so a redraw does not
    /// yank the map back while the user is panning.
    @MainActor
    final class Coordinator: NSObject, GMSMapViewDelegate {
        var onPick: (CLLocationCoordinate2D) -> Void = { _ in }
        var marker: GMSMarker?
        var appliedFocus: PlaceMapFocus?

        /// The SDK calls this on the main thread and SwiftUI state lives
        /// there too, so this is an assertion, not a dispatch.
        nonisolated func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            MainActor.assumeIsolated { self.onPick(coordinate) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        // Wherever the maps were last looking, until the focus arrives.
        // The country view is for a first launch that has never had a fix.
        if let start = LastMapCenter.load() {
            options.camera = GMSCameraPosition(
                latitude: start.latitude, longitude: start.longitude, zoom: 13
            )
        } else {
            options.camera = GMSCameraPosition(latitude: 39.5, longitude: -98.35, zoom: 3)
        }
        let view = GMSMapView(options: options)
        view.isMyLocationEnabled = true
        view.settings.myLocationButton = true
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: GMSMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onPick = onPick

        if let coordinate {
            let marker = coordinator.marker ?? GMSMarker()
            marker.position = coordinate
            marker.title = markerTitle
            marker.map = view
            coordinator.marker = marker
        } else {
            coordinator.marker?.map = nil
            coordinator.marker = nil
        }

        guard let focus, coordinator.appliedFocus != focus else { return }
        let corners = focus.corners
        let bounds = GMSCoordinateBounds(
            coordinate: CLLocationCoordinate2D(
                latitude: corners.southWest.latitude, longitude: corners.southWest.longitude
            ),
            coordinate: CLLocationCoordinate2D(
                latitude: corners.northEast.latitude, longitude: corners.northEast.longitude
            )
        )
        view.animate(with: GMSCameraUpdate.fit(bounds, withPadding: 24))
        coordinator.appliedFocus = focus
        LastMapCenter.save(focus.center)
    }
}
