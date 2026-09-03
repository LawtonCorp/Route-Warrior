import CoreLocation
import MapKit
import RouteWarriorKit

/// Hands the destination to Apple Maps for turn-by-turn (D-034).
///
/// Apple Maps already owns the car screen: with CarPlay connected it
/// takes over with voice, lane guidance and rerouting that Route Rebel
/// would otherwise have to build and would need Apple's navigation
/// entitlement to show. Recording is untouched — it starts before the
/// hand-off and continues in the background, and the departure snapshot
/// is already taken, so the verdict is the same either way.
enum AppleMapsHandoff {
    /// Driving directions. Route choice is left to Apple Maps: the plan
    /// Route Rebel judges against was snapshotted at departure, so a
    /// different suggestion here cannot move the goalposts.
    static var launchOptions: [String: Any] {
        [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
    }

    /// What Apple Maps is asked to navigate to. A name matters: it is
    /// what the driver reads on the car screen.
    static func mapItem(for coordinate: Coordinate, named name: String) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: coordinate.latitude, longitude: coordinate.longitude
        )))
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.name = trimmed.isEmpty ? "Destination" : trimmed
        return item
    }

    /// Opens Apple Maps. False means it could not be opened and the
    /// caller should fall back to the in-app drive view.
    @discardableResult
    @MainActor
    static func navigate(to coordinate: Coordinate, named name: String) -> Bool {
        mapItem(for: coordinate, named: name).openInMaps(launchOptions: launchOptions)
    }
}
