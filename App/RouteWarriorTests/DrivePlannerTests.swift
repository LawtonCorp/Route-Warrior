import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// The Home screen plans a drive in place (D-026), so the transitions it
/// depends on are checked here: a new destination never wears the old
/// one's route, a late answer never overwrites a newer question, and a
/// planner waiting for a location fix can still be retried.
@MainActor
final class DrivePlannerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func plan(_ provider: PlanSnapshot.Provider, seconds: TimeInterval = 600) -> PlanSnapshot {
        PlanSnapshot(
            provider: provider,
            requestedAt: t0,
            polyline: Polyline(coordinates: [
                Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 0.02),
            ]),
            distanceM: 2_224,
            staticDuration: seconds,
            trafficDuration: seconds
        )
    }

    private func destination(_ name: String) -> DrivePlanner.Destination {
        DrivePlanner.Destination(name: name, coordinate: Coordinate(latitude: 1, longitude: 1), placeID: nil)
    }

    func testStartingDoesNotStrandThePlannerInLoading() {
        let planner = DrivePlanner()
        planner.start(destination("Work"))

        // No fetch has begun yet — the caller may still be waiting for a
        // fix, and the Home screen retries only while `loading` is false.
        XCTAssertFalse(planner.loading)
        XCTAssertFalse(planner.failed)
        XCTAssertTrue(planner.hasDestination)
    }

    func testANewDestinationDropsTheOldPlansImmediately() {
        let planner = DrivePlanner()
        let work = destination("Work")
        planner.start(work)
        planner.beginFetch()
        planner.finish(with: [plan(.appleMaps)], for: work)
        XCTAssertEqual(planner.plans.count, 1)

        planner.start(destination("School"))
        XCTAssertTrue(planner.plans.isEmpty)
    }

    func testALatePlanForTheOldDestinationIsIgnored() {
        let planner = DrivePlanner()
        let work = destination("Work")
        let school = destination("School")
        planner.start(work)
        planner.beginFetch()

        planner.start(school)
        planner.beginFetch()
        // Work's request finally answers, after the driver moved on.
        planner.finish(with: [plan(.appleMaps)], for: work)

        XCTAssertTrue(planner.plans.isEmpty)
        XCTAssertTrue(planner.loading)

        planner.finish(with: [plan(.googleRoutes)], for: school)
        XCTAssertEqual(planner.plans.map(\.provider), [.googleRoutes])
        XCTAssertFalse(planner.loading)
    }

    func testAnEmptyAnswerIsAFailureNotASilentBlank() {
        let planner = DrivePlanner()
        let work = destination("Work")
        planner.start(work)
        planner.beginFetch()
        planner.finish(with: [], for: work)

        XCTAssertTrue(planner.failed)
        XCTAssertFalse(planner.loading)
    }

    func testOnlyTheSurfacesOwnPlanIsDrawnAndTheRestAreListed() {
        let planner = DrivePlanner()
        let work = destination("Work")
        planner.start(work)
        planner.beginFetch()
        planner.finish(with: [plan(.appleMaps), plan(.googleRoutes)], for: work)

        XCTAssertEqual(planner.plan(on: .appleMaps)?.provider, .appleMaps)
        XCTAssertEqual(planner.others(on: .appleMaps).map(\.provider), [.googleRoutes])
    }

    func testPromotingAnAlternateReplacesOnlyThatProvidersPlan() {
        let planner = DrivePlanner()
        let work = destination("Work")
        var apple = plan(.appleMaps, seconds: 600)
        apple.alternates = [PlanSnapshot.AltRoute(
            polyline: apple.polyline, staticDuration: 400, trafficDuration: 400
        )]
        let google = plan(.googleRoutes, seconds: 900)
        planner.start(work)
        planner.beginFetch()
        planner.finish(with: [apple, google], for: work)

        planner.promote(alternate: 0, on: .appleMaps)

        XCTAssertEqual(planner.plan(on: .appleMaps)?.trafficDuration, 400)
        XCTAssertEqual(planner.plan(on: .googleRoutes)?.trafficDuration, 900)
    }

    func testClearingLeavesNothingBehind() {
        let planner = DrivePlanner()
        let work = destination("Work")
        planner.start(work)
        planner.beginFetch()
        planner.finish(with: [], for: work)
        planner.clear()

        XCTAssertFalse(planner.hasDestination)
        XCTAssertTrue(planner.plans.isEmpty)
        XCTAssertFalse(planner.failed)
        XCTAssertFalse(planner.loading)
    }
}
