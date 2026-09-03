import Foundation
import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// The wording the driver reads at speed, and the same wording the car
/// screen will read (D-035). Getting "ahead" and "behind" the wrong way
/// round is the one mistake that would make the app lie.
final class ScoreboardTextTests: XCTestCase {
    private func board(ahead: Double?, ghost: Double? = nil, progress: Double = 0.5, offPlan: Bool = false) -> DriveScoreboard {
        DriveScoreboard(
            aheadOfPlanSeconds: ahead,
            aheadOfGhostSeconds: ghost,
            elapsed: 600,
            progress: progress,
            offPlan: offPlan
        )
    }

    func testAheadAndBehindAreNeverTheWrongWayRound() {
        XCTAssertTrue(ScoreboardText.standing(92).hasSuffix("ahead"))
        XCTAssertTrue(ScoreboardText.standing(-92).hasSuffix("behind"))
        XCTAssertTrue(ScoreboardText.headline(board(ahead: 92), provider: "Google").contains("ahead of Google"))
        XCTAssertTrue(ScoreboardText.headline(board(ahead: -92), provider: "Google").contains("behind Google"))
    }

    /// A gap of a second or two flips sign constantly; at a glance that
    /// reads as a broken app.
    func testATinyGapReadsAsLevelNotAsChurn() {
        XCTAssertEqual(ScoreboardText.standing(2), "level")
        XCTAssertEqual(ScoreboardText.standing(-2), "level")
        XCTAssertEqual(ScoreboardText.standing(0), "level")
        XCTAssertEqual(ScoreboardText.headline(board(ahead: 1), provider: "Apple"), "Level with Apple")
    }

    func testTheMarginIsAnEdgeNotAGap() {
        // Exactly at the margin is a standing, just past it is too.
        XCTAssertNotEqual(ScoreboardText.standing(ScoreboardText.levelMarginSeconds), "level")
        XCTAssertEqual(ScoreboardText.standing(ScoreboardText.levelMarginSeconds - 0.1), "level")
    }

    func testWithNoPlanTheHeadlineSaysSoRatherThanClaimingAWin() {
        XCTAssertEqual(
            ScoreboardText.headline(board(ahead: nil), provider: "Google"),
            "Recording — no plan to race"
        )
    }

    func testTheVerdictLeadsTheRows() throws {
        let rows = ScoreboardText.rows(board(ahead: 92, progress: 0.62), provider: "Google")
        XCTAssertEqual(rows.first?.label, "vs Google")
        XCTAssertEqual(try XCTUnwrap(rows.first).value, ScoreboardText.standing(92))
        XCTAssertTrue(rows.contains(ScoreboardText.Row(label: "Progress", value: "62%")))
        XCTAssertTrue(rows.contains(where: { $0.label == "Elapsed" }))
    }

    func testWithoutAPlanTheRowsDropTheRaceButKeepTheDrive() {
        let rows = ScoreboardText.rows(board(ahead: nil), provider: "Google")
        XCTAssertFalse(rows.contains(where: { $0.label.hasPrefix("vs ") }))
        XCTAssertFalse(rows.contains(where: { $0.label == "Progress" }))
        XCTAssertTrue(rows.contains(where: { $0.label == "Elapsed" }))
    }

    func testTheGhostRaceGetsItsOwnRowOnlyWhenItIsRunning() {
        XCTAssertTrue(ScoreboardText.rows(board(ahead: 10, ghost: -30), provider: "Google")
            .contains(ScoreboardText.Row(label: "vs your own", value: "0:30 behind")))
        XCTAssertFalse(ScoreboardText.rows(board(ahead: 10), provider: "Google")
            .contains(where: { $0.label == "vs your own" }))
    }

    func testLeavingThePlanIsSaidPlainly() {
        XCTAssertTrue(ScoreboardText.rows(board(ahead: 10, offPlan: true), provider: "Google")
            .contains(ScoreboardText.Row(label: "Route", value: "Off the plan")))
        XCTAssertTrue(ScoreboardText.rows(board(ahead: 10), provider: "Google")
            .contains(ScoreboardText.Row(label: "Route", value: "On the plan")))
    }
}
