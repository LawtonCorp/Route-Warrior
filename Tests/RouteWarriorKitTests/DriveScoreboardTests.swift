import Foundation
import XCTest

@testable import RouteWarriorKit

/// "Am I beating Google right now?" — the number the drive banner and the
/// car screen both read (D-035). The expectations here are structural:
/// on a two-point line the halfway point is halfway, whatever the line
/// measures in metres.
final class DriveScoreboardTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    /// Due east along the equator, so distance is proportional to
    /// longitude and the midpoint is exactly halfway.
    private let line = Polyline(coordinates: [
        Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 0.02),
    ])
    private let midpoint = Coordinate(latitude: 0, longitude: 0.01)

    private func plan(seconds: TimeInterval = 600) -> PlanSnapshot {
        PlanSnapshot(
            provider: .googleRoutes,
            requestedAt: t0,
            polyline: line,
            distanceM: line.lengthMeters,
            staticDuration: seconds,
            trafficDuration: seconds
        )
    }

    func testHalfwayInHalfTheETAIsDeadLevel() {
        let board = DriveScoreboard.board(elapsed: 300, position: midpoint, plan: plan())
        XCTAssertEqual(try XCTUnwrap(board.aheadOfPlanSeconds), 0, accuracy: 0.5)
        XCTAssertEqual(board.progress, 0.5, accuracy: 0.01)
    }

    func testGettingHalfwayEarlyPutsYouAhead() throws {
        let board = DriveScoreboard.board(elapsed: 240, position: midpoint, plan: plan())
        XCTAssertEqual(try XCTUnwrap(board.aheadOfPlanSeconds), 60, accuracy: 0.5)
    }

    func testDawdlingPutsYouBehind() throws {
        let board = DriveScoreboard.board(elapsed: 420, position: midpoint, plan: plan())
        XCTAssertEqual(try XCTUnwrap(board.aheadOfPlanSeconds), -120, accuracy: 0.5)
    }

    func testWithNoPlanThereIsNothingToRace() {
        let board = DriveScoreboard.board(elapsed: 300, position: midpoint, plan: nil)
        XCTAssertNil(board.aheadOfPlanSeconds)
        XCTAssertFalse(board.racesThePlan)
        XCTAssertEqual(board.progress, 0)
        XCTAssertEqual(board.elapsed, 300)
    }

    func testAPlanWithNoLengthOrNoETAIsNotAPace() {
        let empty = PlanSnapshot(
            provider: .googleRoutes,
            requestedAt: t0,
            polyline: Polyline(coordinates: [Coordinate(latitude: 0, longitude: 0)]),
            distanceM: 0,
            staticDuration: 600,
            trafficDuration: 600
        )
        XCTAssertNil(DriveScoreboard.planPace(for: empty))
        XCTAssertNil(DriveScoreboard.planPace(for: plan(seconds: 0)))
        XCTAssertNil(DriveScoreboard.board(elapsed: 60, position: midpoint, plan: empty).aheadOfPlanSeconds)
    }

    func testProgressNeverLeavesTheRoute() {
        let past = Coordinate(latitude: 0, longitude: 0.9)
        let before = Coordinate(latitude: 0, longitude: -0.9)
        XCTAssertEqual(DriveScoreboard.board(elapsed: 600, position: past, plan: plan()).progress, 1, accuracy: 0.001)
        XCTAssertEqual(DriveScoreboard.board(elapsed: 1, position: before, plan: plan()).progress, 0, accuracy: 0.001)
    }

    func testTheGhostRaceStandingIsCarriedThroughUnchanged() throws {
        let ghost = GhostRace.Status(
            aheadSeconds: -42, distanceAlongM: 100, routeLengthM: 200,
            myElapsed: 300, referenceElapsed: 258
        )
        let board = DriveScoreboard.board(elapsed: 300, position: midpoint, plan: plan(), ghost: ghost)
        XCTAssertEqual(try XCTUnwrap(board.aheadOfGhostSeconds), -42)
    }

    func testLeavingThePlanIsRecordedButStillScored() throws {
        let board = DriveScoreboard.board(
            elapsed: 240, position: midpoint, plan: plan(), offPlan: true
        )
        XCTAssertTrue(board.offPlan)
        // Off the plan is not off the clock: the ETA is still the thing
        // being beaten.
        XCTAssertEqual(try XCTUnwrap(board.aheadOfPlanSeconds), 60, accuracy: 0.5)
    }
}
