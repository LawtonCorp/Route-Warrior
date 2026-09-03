import Foundation
import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// The trip screen offers a way into a destination's analytics, and the
/// free tier only analyzes the first saved places. The rank it gates on
/// has to be the Places tab's own order, or the same place would be free
/// in one screen and locked in the other.
final class DestinationAnalyticsTests: XCTestCase {
    func testRankIsThePositionInTheSavedPlaceOrder() {
        let home = UUID(), work = UUID(), school = UUID()
        let places = [home, work, school]

        XCTAssertEqual(DestinationAnalytics.rank(of: home, in: places), 0)
        XCTAssertEqual(DestinationAnalytics.rank(of: work, in: places), 1)
        XCTAssertEqual(DestinationAnalytics.rank(of: school, in: places), 2)
    }

    func testATripThatEndedNowhereSavedHasNoRank() {
        XCTAssertNil(DestinationAnalytics.rank(of: nil, in: [UUID()]))
        XCTAssertNil(DestinationAnalytics.rank(of: UUID(), in: [UUID()]))
    }

    /// The gate the rank feeds: with the default limit of two, the third
    /// saved place is Pro on every screen that offers analytics.
    func testTheRankAgreesWithTheTierGate() throws {
        let places = [UUID(), UUID(), UUID()]
        let policy = TierPolicy()

        let third = try XCTUnwrap(DestinationAnalytics.rank(of: places[2], in: places))
        XCTAssertFalse(policy.canAnalyzeDestination(atRank: third, tier: .free))
        XCTAssertTrue(policy.canAnalyzeDestination(atRank: third, tier: .pro))

        let first = try XCTUnwrap(DestinationAnalytics.rank(of: places[0], in: places))
        XCTAssertTrue(policy.canAnalyzeDestination(atRank: first, tier: .free))
    }
}
