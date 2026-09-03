import CoreLocation
import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// The New Place map frames itself from a `PlaceMapFocus`, and both
/// surfaces read the same corners from it. The arithmetic is flat-earth,
/// so it is checked against CoreLocation's geodesic distance — a
/// genuinely independent implementation, not this one agreeing with
/// itself.
final class PlaceMapFocusTests: XCTestCase {
    private func metres(_ a: Coordinate, _ b: Coordinate) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    func testCornersSitHalfTheSpanFromTheCentre() {
        let centre = Coordinate(latitude: 40, longitude: -105)
        let focus = PlaceMapFocus(center: centre, spanMeters: 12_000)
        let corners = focus.corners

        // Due north of the centre, and due east of it: each should be
        // half a span away. A sphere and WGS84 disagree by well under 1%.
        let north = metres(centre, Coordinate(latitude: corners.northEast.latitude, longitude: centre.longitude))
        let east = metres(centre, Coordinate(latitude: centre.latitude, longitude: corners.northEast.longitude))
        XCTAssertEqual(north, 6_000, accuracy: 60)
        XCTAssertEqual(east, 6_000, accuracy: 60)

        let south = metres(centre, Coordinate(latitude: corners.southWest.latitude, longitude: centre.longitude))
        let west = metres(centre, Coordinate(latitude: centre.latitude, longitude: corners.southWest.longitude))
        XCTAssertEqual(south, 6_000, accuracy: 60)
        XCTAssertEqual(west, 6_000, accuracy: 60)
    }

    func testTheBoxIsCentredOnTheFocus() {
        let centre = Coordinate(latitude: 37.77, longitude: -122.42)
        let corners = PlaceMapFocus(center: centre, spanMeters: 1_500).corners
        XCTAssertEqual((corners.southWest.latitude + corners.northEast.latitude) / 2, centre.latitude, accuracy: 1e-9)
        XCTAssertEqual((corners.southWest.longitude + corners.northEast.longitude) / 2, centre.longitude, accuracy: 1e-9)
        XCTAssertLessThan(corners.southWest.latitude, corners.northEast.latitude)
        XCTAssertLessThan(corners.southWest.longitude, corners.northEast.longitude)
    }

    func testLongitudeWidensAwayFromTheEquator() {
        let span = 10_000.0
        let atEquator = PlaceMapFocus(center: Coordinate(latitude: 0, longitude: 0), spanMeters: span).corners
        let atSixty = PlaceMapFocus(center: Coordinate(latitude: 60, longitude: 0), spanMeters: span).corners

        // On the equator a degree each way covers the same ground.
        XCTAssertEqual(atEquator.northEast.latitude, atEquator.northEast.longitude, accuracy: 1e-9)
        // At 60°, cos 60° = 0.5, so the same metres need twice the degrees.
        XCTAssertEqual(atSixty.northEast.longitude, atEquator.northEast.longitude * 2, accuracy: 1e-6)
    }

    func testThePolesStayFinite() {
        let corners = PlaceMapFocus(center: Coordinate(latitude: 89.999, longitude: 12), spanMeters: 12_000).corners
        XCTAssertTrue(corners.northEast.longitude.isFinite)
        XCTAssertTrue(corners.southWest.longitude.isFinite)
    }

    /// Equality is what stops a redraw from yanking the camera back while
    /// the user is panning: the same focus must compare equal.
    func testEqualFocusesCompareEqualSoTheCameraIsLeftAlone() {
        let centre = Coordinate(latitude: 40, longitude: -105)
        XCTAssertEqual(
            PlaceMapFocus(center: centre, spanMeters: 12_000),
            PlaceMapFocus(center: centre, spanMeters: 12_000)
        )
        XCTAssertNotEqual(
            PlaceMapFocus(center: centre, spanMeters: 12_000),
            PlaceMapFocus(center: centre, spanMeters: 1_500)
        )
    }
}
