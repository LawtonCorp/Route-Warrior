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

    /// The plan drawn on a surface, unwrapped without `try` so the
    /// assertions below read as one line each.
    private func shown(_ snapshot: PlanSnapshot?) -> PlanSnapshot {
        guard let snapshot else {
            XCTFail("no plan for that surface")
            return plan(.appleMaps)
        }
        return snapshot
    }

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

    func testEveryProvidersPlanIsKeptButOnlyTheSurfacesOwnIsDrawn() {
        let planner = DrivePlanner()
        let work = destination("Work")
        planner.start(work)
        planner.beginFetch()
        planner.finish(with: [plan(.appleMaps), plan(.googleRoutes)], for: work)

        // Both are held, so the drive is still compared against both
        // (D-022); the surface simply draws one of them.
        XCTAssertEqual(planner.plans.count, 2)
        XCTAssertEqual(planner.plan(on: .appleMaps)?.provider, .appleMaps)
        XCTAssertEqual(planner.plan(on: .googleRoutes)?.provider, .googleRoutes)
    }

    // MARK: Picking a route without moving the list (D-063)

    /// Apple with two alternates, plus a Google plan to prove the pick
    /// touches only the surface it was made on.
    private func plannerWithAlternates() -> DrivePlanner {
        let planner = DrivePlanner()
        let work = destination("Work")
        var apple = plan(.appleMaps, seconds: 600)
        apple.alternates = [
            PlanSnapshot.AltRoute(polyline: apple.polyline, staticDuration: 400, trafficDuration: 400),
            PlanSnapshot.AltRoute(polyline: apple.polyline, staticDuration: 800, trafficDuration: 800),
        ]
        planner.start(work)
        planner.beginFetch()
        planner.finish(with: [apple, plan(.googleRoutes, seconds: 900)], for: work)
        return planner
    }

    func testPickingAnAlternateDepartsWithItAndTouchesNoOtherProvider() {
        let planner = plannerWithAlternates()
        planner.select(route: 1, on: .appleMaps)

        let departure = planner.departurePlans(on: .appleMaps)
        XCTAssertEqual(departure.first { $0.provider == .appleMaps }?.trafficDuration, 400)
        XCTAssertEqual(departure.first { $0.provider == .googleRoutes }?.trafficDuration, 900)
    }

    /// The defect this replaced: every tap rewrote the stored plans, so
    /// the rows renumbered under the finger and a second tap promoted a
    /// promotion. The list must read the same before and after.
    func testTheListOnScreenNeverMovesWhenAPickIsMade() {
        let planner = plannerWithAlternates()
        let before = PlanList.rows(shown(planner.plan(on: .appleMaps)))

        planner.select(route: 2, on: .appleMaps)
        XCTAssertEqual(PlanList.rows(shown(planner.plan(on: .appleMaps))), before)

        planner.select(route: 1, on: .appleMaps)
        XCTAssertEqual(PlanList.rows(shown(planner.plan(on: .appleMaps))), before)
        // And the pick still means what it says after changing your mind.
        XCTAssertEqual(
            planner.departurePlans(on: .appleMaps).first { $0.provider == .appleMaps }?.trafficDuration, 400
        )
    }

    /// Picking the same row twice lands where picking it once did.
    func testPickingTheSameRowTwiceIsNotAPromotionOfAPromotion() {
        let planner = plannerWithAlternates()
        planner.select(route: 2, on: .appleMaps)
        let once = planner.departurePlans(on: .appleMaps)
        planner.select(route: 2, on: .appleMaps)
        XCTAssertEqual(planner.departurePlans(on: .appleMaps), once)
        XCTAssertEqual(once.first { $0.provider == .appleMaps }?.trafficDuration, 800)
    }

    func testANewAnswerClearsAPickMadeAgainstTheOldList() {
        let planner = plannerWithAlternates()
        planner.select(route: 2, on: .appleMaps)
        XCTAssertEqual(planner.selectedRoute, 2)

        let work = destination("Work")
        planner.beginFetch()
        planner.finish(with: [plan(.appleMaps, seconds: 700)], for: work)
        XCTAssertEqual(planner.selectedRoute, PlanList.recommendedRow, "a row number means nothing here")

        planner.select(route: 4, on: .appleMaps)
        XCTAssertEqual(planner.selectedRoute, PlanList.recommendedRow, "and a row that does not exist is refused")
    }

    /// A new destination cannot inherit the last one's pick.
    func testANewDestinationClearsThePick() {
        let planner = plannerWithAlternates()
        planner.select(route: 1, on: .appleMaps)
        planner.start(destination("School"))
        XCTAssertEqual(planner.selectedRoute, PlanList.recommendedRow)
    }

    func testOnlyTheEndOfARecordingTakesThePlanOffTheScreen() {
        // The trip was saved: the plan it was driven against goes.
        XCTAssertTrue(DrivePlanner.planEnds(recordingWas: true, now: false, hasDestination: true))
        // Recording starting, or the recorder already idle, changes nothing.
        XCTAssertFalse(DrivePlanner.planEnds(recordingWas: false, now: true, hasDestination: true))
        XCTAssertFalse(DrivePlanner.planEnds(recordingWas: false, now: false, hasDestination: true))
        // Nothing to clear.
        XCTAssertFalse(DrivePlanner.planEnds(recordingWas: true, now: false, hasDestination: false))
    }

    /// D-044: the button under the plans is never greyed out. It says
    /// Go while the providers are being asked, and "without a plan" only
    /// once they have answered with nothing.
    func testTheGoButtonSaysGoUntilTheProvidersHaveSaidNo() {
        let planner = DrivePlanner()
        let home = destination("Home")
        planner.start(home)
        XCTAssertEqual(planner.goTitle, "Drive without a plan")
        planner.beginFetch()
        XCTAssertEqual(planner.goTitle, "Go")
        planner.finish(with: [], for: home)
        XCTAssertEqual(planner.goTitle, "Drive without a plan")
        planner.start(home)
        planner.beginFetch()
        planner.finish(with: [plan(.appleMaps)], for: home)
        XCTAssertEqual(planner.goTitle, "Go")
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
