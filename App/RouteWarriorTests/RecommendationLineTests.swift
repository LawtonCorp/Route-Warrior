import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// D-065: the "right now" line adds to the head-to-head card, never
/// repeats it.
final class RecommendationLineTests: XCTestCase {
    private func route(_ name: String, median: TimeInterval, count: Int) -> RouteRaceEngine.Route {
        RouteRaceEngine.Route(
            id: UUID(), name: name,
            stats: .init(count: count, mean: median, median: median, best: median, worst: median)
        )
    }

    private func recommendation(
        outcome: RouteRaceEngine.Outcome, tier: RouteRecommender.Tier
    ) -> RouteRecommender.Recommendation {
        let routes = [route("via Maple Ave", median: 1_080, count: 5), route("the back way", median: 1_200, count: 5)]
        return .init(
            race: .init(routes: routes, outcome: outcome),
            tier: tier,
            context: .init(weekday: 3, bucket: 2),   // Tuesday, 8am–noon
            drivesCounted: 10
        )
    }

    func testANarrowAnswerBecomesALineWithItsScopeAndItsEvidence() {
        let line = RecommendationLine.text(for: recommendation(
            outcome: .winner(gapSeconds: 120, confidence: .medium), tier: .weekdaySlot
        ))
        XCTAssertEqual(line, "Right now: via Maple Ave is usually fastest on Tuesday mornings · 10 drives")
    }

    func testATieIsSaidNotWidened() {
        let line = RecommendationLine.text(for: recommendation(outcome: .tie(gapSeconds: 10), tier: .dayClassSlot))
        XCTAssertEqual(line, "Right now: No clear winner on weekday mornings · 10 drives")
    }

    /// The card above already says what every drive says.
    func testTheAllDrivesTierAddsNothing() {
        XCTAssertNil(RecommendationLine.text(for: recommendation(
            outcome: .winner(gapSeconds: 120, confidence: .high), tier: .all
        )))
    }

    func testCollectingAndNothingAreSilent() {
        XCTAssertNil(RecommendationLine.text(for: recommendation(outcome: .collecting(drivesNeeded: 2), tier: .slot)))
        XCTAssertNil(RecommendationLine.text(for: nil))
    }
}
