import CoreLocation
import MapKit
import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// Departure hands the destination to Apple Maps so CarPlay gets real
/// turn-by-turn (D-034). What is handed over has to be right: the wrong
/// coordinate or a missing mode sends the driver somewhere else.
final class AppleMapsHandoffTests: XCTestCase {
    private let lifetime = Coordinate(latitude: 39.7098, longitude: -104.9387)

    func testTheHandoffAsksForDrivingDirections() {
        XCTAssertEqual(
            AppleMapsHandoff.launchOptions[MKLaunchOptionsDirectionsModeKey] as? String,
            MKLaunchOptionsDirectionsModeDriving
        )
    }

    func testTheDestinationAndItsNameSurviveTheHandoff() {
        let item = AppleMapsHandoff.mapItem(for: lifetime, named: "Lifetime")
        XCTAssertEqual(item.name, "Lifetime")
        XCTAssertEqual(item.placemark.coordinate.latitude, lifetime.latitude, accuracy: 1e-6)
        XCTAssertEqual(item.placemark.coordinate.longitude, lifetime.longitude, accuracy: 1e-6)
    }

    func testAnUnnamedDestinationStillReadsOnTheCarScreen() {
        XCTAssertEqual(AppleMapsHandoff.mapItem(for: lifetime, named: "").name, "Destination")
        XCTAssertEqual(AppleMapsHandoff.mapItem(for: lifetime, named: "   ").name, "Destination")
    }

    func testAStoredNameIsNotPaddedWithWhitespace() {
        XCTAssertEqual(AppleMapsHandoff.mapItem(for: lifetime, named: "  Gym  ").name, "Gym")
    }
}
