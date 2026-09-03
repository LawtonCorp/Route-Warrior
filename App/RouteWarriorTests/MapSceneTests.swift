import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// D-022 §9.2 in one place: a surface draws only its own provider's
/// plans and reroute; the rest are listed as numbers. Both surfaces
/// render the same scene, so this rule is what keeps the terms clean.
final class MapSceneTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let line = Polyline(coordinates: [
        Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 0.02),
    ])

    private func plan(_ provider: PlanSnapshot.Provider) -> PlanSnapshot {
        PlanSnapshot(provider: provider, requestedAt: t0, polyline: line, distanceM: 2_224, staticDuration: 300, trafficDuration: 300)
    }

    func testEachSurfaceDrawsOnlyItsOwnProvidersPlans() {
        let apple = plan(.appleMaps)
        let google = plan(.googleRoutes)
        let scene = MapScene(plans: [apple, google], reroute: plan(.googleRoutes))

        XCTAssertEqual(scene.drawablePlans(for: .appleMaps).map(\.id), [apple.id])
        XCTAssertEqual(scene.drawablePlans(for: .googleRoutes).map(\.id), [google.id])
        XCTAssertNil(scene.drawableReroute(for: .appleMaps))
        XCTAssertNotNil(scene.drawableReroute(for: .googleRoutes))
        XCTAssertEqual(scene.undrawnPlans(for: .appleMaps).map(\.id), [google.id])
        XCTAssertEqual(scene.undrawnPlans(for: .googleRoutes).map(\.id), [apple.id])
    }

    func testAnEmptySceneFramesTheDriverInsteadOfTheWholeCountry() {
        let here = Coordinate(latitude: 39.74, longitude: -104.98)
        let empty = MapScene(userLocation: here)
        // Nothing to draw on either surface, so both settle over the driver.
        XCTAssertEqual(empty.fallbackCenter(for: .appleMaps), here)
        XCTAssertEqual(empty.fallbackCenter(for: .googleRoutes), here)

        // Once a plan exists for a surface, that surface frames the route
        // and ignores the driver's location.
        let planned = MapScene(plans: [plan(.appleMaps)], userLocation: here)
        XCTAssertNil(planned.fallbackCenter(for: .appleMaps))
        XCTAssertEqual(planned.fallbackCenter(for: .googleRoutes), here)
    }

    func testWithNoLocationYetThereIsNothingToFallBackTo() {
        XCTAssertNil(MapScene().fallbackCenter(for: .appleMaps))
    }

    func testFitContentGathersOnlyWhatTheSurfaceDraws() {
        let apple = plan(.appleMaps)
        let scene = MapScene(plans: [apple], trail: [Coordinate(latitude: 1, longitude: 1)])
        // Apple's surface frames the trail plus Apple's line; Google's
        // surface has no plan to draw here, so it frames the trail alone.
        XCTAssertEqual(scene.allCoordinates(for: .appleMaps).count, 1 + line.coordinates.count)
        XCTAssertEqual(scene.allCoordinates(for: .googleRoutes).count, 1)
        XCTAssertEqual(scene.destination(for: .appleMaps), line.coordinates.last)
        XCTAssertNil(scene.destination(for: .googleRoutes))
    }

    func testTrailOnlySceneStillFrames() {
        let scene = MapScene(trail: [Coordinate(latitude: 1, longitude: 1), Coordinate(latitude: 1.01, longitude: 1)])
        XCTAssertEqual(scene.allCoordinates(for: .appleMaps).count, 2)
        XCTAssertNil(scene.destination(for: .appleMaps))
        let region = AppleMapSurface.region(fitting: scene.allCoordinates(for: .appleMaps))
        XCTAssertEqual(region.center.latitude, 1.005, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(region.span.latitudeDelta, 0.01)
    }
}
