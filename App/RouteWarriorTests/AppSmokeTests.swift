import RouteWarriorKit
import XCTest
@testable import RouteWarrior

/// The app target needs at least one real test, because a green kit suite
/// says nothing about wiring. The deeper wiring lives in
/// RecordingPipelineTests; this remains the cheapest link check.
final class AppSmokeTests: XCTestCase {
    func testAppLinksTheKit() {
        let chicago = Coordinate(latitude: 41.8781, longitude: -87.6298)
        let evanston = Coordinate(latitude: 42.0451, longitude: -87.6877)
        let distance = Geo.distanceMeters(from: chicago, to: evanston)
        // ~19 km apart; the exact value is the kit's own test's job.
        XCTAssertGreaterThan(distance, 15_000)
        XCTAssertLessThan(distance, 25_000)
    }
}
