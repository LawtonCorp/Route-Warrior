import Foundation
import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// Two complaints from the road: every map opened on the whole country
/// while it waited for a fix, and the drive view snapped back to its own
/// zoom a second after any pinch (D-036).
final class MapCameraTests: XCTestCase {
    private func freshDefaults() throws -> (UserDefaults, () -> Void) {
        let name = "MapCameraTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    // MARK: Where the map opens

    func testTheLastCentreSurvivesARelaunch() throws {
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }
        let denver = Coordinate(latitude: 39.7392, longitude: -104.9903)

        XCTAssertNil(LastMapCenter.load(from: defaults))
        LastMapCenter.save(denver, to: defaults)
        let restored = try XCTUnwrap(LastMapCenter.load(from: defaults))
        XCTAssertEqual(restored.latitude, denver.latitude, accuracy: 1e-9)
        XCTAssertEqual(restored.longitude, denver.longitude, accuracy: 1e-9)
    }

    /// An unset pair of doubles reads as Null Island. Opening the map in
    /// the Gulf of Guinea is no better than opening it over Kansas.
    func testNullIslandIsNotSomewhereTheDriverHasBeen() throws {
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }

        LastMapCenter.save(Coordinate(latitude: 0, longitude: 0), to: defaults)
        XCTAssertNil(LastMapCenter.load(from: defaults))
        XCTAssertNil(LastMapCenter.valid(Coordinate(latitude: 0, longitude: 0)))
    }

    func testACoordinateOffTheGlobeIsRefused() throws {
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }

        LastMapCenter.save(Coordinate(latitude: 91, longitude: 0), to: defaults)
        XCTAssertNil(LastMapCenter.load(from: defaults))
        XCTAssertNil(LastMapCenter.valid(Coordinate(latitude: 0, longitude: 181)))
        XCTAssertNotNil(LastMapCenter.valid(Coordinate(latitude: -89.9, longitude: 179.9)))
    }

    // MARK: The zoom the driver chose

    func testTheFirstFollowUsesTheDrivingZoom() {
        XCTAssertEqual(GoogleMapSurface.followZoom(applied: nil, current: 3), GoogleMapSurface.drivingZoom)
    }

    func testAPinchIsKeptRatherThanUndoneASecondLater() {
        // The driver zoomed out from 16 to 12; following must not drag
        // them back.
        XCTAssertEqual(GoogleMapSurface.followZoom(applied: 16, current: 12), 12)
        XCTAssertEqual(GoogleMapSurface.followZoom(applied: 12, current: 17.5), 17.5)
    }

    func testAnAnimationStillSettlingIsNotAPinch() {
        let drift = GoogleMapSurface.zoomDriftTolerance / 2
        XCTAssertEqual(GoogleMapSurface.followZoom(applied: 16, current: 16 + drift), 16)
        XCTAssertEqual(GoogleMapSurface.followZoom(applied: 16, current: 16 - drift), 16)
    }

    func testOnceKeptTheDriversZoomIsStable() {
        // Feeding the result back in, tick after tick, must not drift.
        var zoom = GoogleMapSurface.followZoom(applied: 16, current: 11)
        for _ in 0..<20 {
            zoom = GoogleMapSurface.followZoom(applied: zoom, current: zoom)
        }
        XCTAssertEqual(zoom, 11)
    }
}
