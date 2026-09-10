import Foundation
import RouteWarriorKit
import UIKit

/// Which navigation app, if any, Go hands the destination to (D-034,
/// D-057). Off keeps the driver on Route Rebel's own drive view.
enum NavigationHandoff: String, CaseIterable, Sendable {
    case off
    case appleMaps
    case googleMaps

    var label: String {
        switch self {
        case .off: "Off"
        case .appleMaps: "Apple Maps"
        case .googleMaps: "Google Maps"
        }
    }
}

/// Hands the destination to the Google Maps app (D-057), the way
/// `AppleMapsHandoff` hands it to Apple Maps. Google publishes a
/// universal link for this: with the app installed it opens Google Maps
/// straight into navigation, and without it the same link opens the
/// browser's directions page, so there is nothing to detect and no URL
/// scheme to declare. Google Maps picks its own route, which is usually
/// the one Route Rebel snapshotted and is not guaranteed to be; the
/// snapshot stays the baseline either way (D-010).
enum GoogleMapsHandoff {
    /// `https://www.google.com/maps/dir/?api=1&destination=lat,lng
    /// &travelmode=driving&dir_action=navigate` — Google's Maps URLs
    /// contract. Coordinates rather than a name, so the pin is exact.
    static func url(for coordinate: Coordinate) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/maps/dir/"
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(
                name: "destination",
                value: String(format: "%.6f,%.6f", coordinate.latitude, coordinate.longitude)
            ),
            URLQueryItem(name: "travelmode", value: "driving"),
            URLQueryItem(name: "dir_action", value: "navigate"),
        ]
        return components.url!
    }

    /// Opens Google Maps (or the browser). True once the hand-off has
    /// been asked for; the caller then leaves the drive view closed.
    @discardableResult
    @MainActor
    static func navigate(to coordinate: Coordinate) -> Bool {
        UIApplication.shared.open(url(for: coordinate))
        return true
    }
}
