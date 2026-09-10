import RouteWarriorKit
import XCTest
@testable import RouteWarrior

/// D-050: the paywall counts what is already recorded and locked. The
/// numbers come from the same policy that does the locking, so the
/// paywall can never promise something the gate does not hold.
final class LockedDataSummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let home = UUID(), work = UUID(), gym = UUID(), coffee = UUID()

    private func trip(daysAgo: Double, to place: UUID?, stops: Int = 0) -> LockedDataSummary.TripFacts {
        LockedDataSummary.TripFacts(
            startedAt: now.addingTimeInterval(-daysAgo * 86_400),
            destinationPlaceID: place,
            stopCount: stops
        )
    }

    func testCountsOlderTripsLockedDestinationsAndStops() {
        let trips = [
            trip(daysAgo: 1, to: home, stops: 3),
            trip(daysAgo: 29, to: work, stops: 4),
            trip(daysAgo: 31, to: gym, stops: 2),
            trip(daysAgo: 90, to: gym, stops: 5),
            trip(daysAgo: 200, to: nil, stops: 1),
        ]
        // Saved in this order: home and work are free; gym is locked and
        // visited; coffee is locked but never driven to, so not a loss.
        let summary = LockedDataSummary.compute(trips: trips, placeIDs: [home, work, gym, coffee], now: now)
        XCTAssertEqual(summary, LockedDataSummary(olderTrips: 3, lockedDestinations: 1, stops: 15))
        XCTAssertFalse(summary.isEmpty)
    }

    func testANewInstallHasNothingLocked() {
        let summary = LockedDataSummary.compute(trips: [], placeIDs: [home, work, gym], now: now)
        XCTAssertEqual(summary, LockedDataSummary(olderTrips: 0, lockedDestinations: 0, stops: 0))
        XCTAssertTrue(summary.isEmpty)
        XCTAssertEqual(PaywallText.lockedLines(summary, historyDays: 30), [])
    }

    func testTheLinesReadAsCountsWithTheRightPlurals() {
        let one = LockedDataSummary(olderTrips: 1, lockedDestinations: 1, stops: 1)
        XCTAssertEqual(PaywallText.lockedLines(one, historyDays: 30), [
            "1 drive older than 30 days",
            "1 more destination to analyze",
            "1 stop, signal by signal",
        ])
        let many = LockedDataSummary(olderTrips: 47, lockedDestinations: 0, stops: 212)
        XCTAssertEqual(PaywallText.lockedLines(many, historyDays: 30), [
            "47 drives older than 30 days",
            "212 stops, signal by signal",
        ])
    }

    func testThePriceLineLeadsWithTheTrial() {
        XCTAssertEqual(PaywallText.priceLine(displayPrice: "$24.99", period: "year", trialDays: 7), "7 days free, then $24.99 per year")
        XCTAssertEqual(PaywallText.priceLine(displayPrice: "$3.99", period: "month", trialDays: nil), "$3.99 per month")
        XCTAssertEqual(PaywallText.priceLine(displayPrice: "$3.99", period: "month", trialDays: 0), "$3.99 per month")
    }
}
