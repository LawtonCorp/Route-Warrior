import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// D-057: Go can hand the destination to Google Maps. The link is
/// Google's published Maps URL contract, and what it carries has to be
/// right: the coordinate, driving, and straight into navigation.
final class GoogleMapsHandoffTests: XCTestCase {
    private let lifetime = Coordinate(latitude: 39.7098, longitude: -104.9387)

    func testTheLinkIsGooglesDirectionsContract() throws {
        let url = GoogleMapsHandoff.url(for: lifetime)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "www.google.com")
        XCTAssertEqual(components.path, "/maps/dir/")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["api"], "1")
        XCTAssertEqual(query["destination"], "39.709800,-104.938700")
        XCTAssertEqual(query["travelmode"], "driving")
        XCTAssertEqual(query["dir_action"], "navigate")
    }

    func testTheChoicesReadAsAppNames() {
        XCTAssertEqual(NavigationHandoff.allCases.map(\.label), ["Off", "Apple Maps", "Google Maps"])
        XCTAssertEqual(NavigationHandoff(rawValue: "appleMaps"), .appleMaps)
    }
}
