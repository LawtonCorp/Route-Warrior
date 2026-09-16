import Foundation
import XCTest

@testable import RouteWarriorKit

/// D-065: which of my own routes to take *now*, drawn as narrowly as the
/// data allows and saying how narrowly that was.
final class RouteRecommenderTests: XCTestCase {
    /// Sunday 2023-11-12 00:00 UTC: weekday 1, bucket 0. Every drive is
    /// placed relative to it so weekday and slot are exact.
    private let sunday = Date(timeIntervalSince1970: 1_699_747_200)
    private let origin = UUID()
    private let destination = UUID()
    private let maple = UUID()
    private let backWay = UUID()
    private let line = Polyline(coordinates: [
        Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 0.01),
    ])

    /// Tuesday, 8am–noon.
    private let tuesdayMorning = RouteRecommender.Context(weekday: 3, bucket: 2)

    private var variants: [RouteVariant] {
        [
            RouteVariant(id: maple, originPlaceID: origin, destinationPlaceID: destination,
                         representativePolyline: line, autoName: "via Maple Ave"),
            RouteVariant(id: backWay, originPlaceID: origin, destinationPlaceID: destination,
                         representativePolyline: line, autoName: "the back way"),
        ]
    }

    /// `count` drives on `variant`, each on the given weekday (1 = Sunday)
    /// at `hour`, spread across successive weeks so no two share a start.
    private func drives(
        _ variant: UUID, count: Int, weekday: Int, hour: Int, minutes: Double, excluded: Bool = false
    ) -> [Trip] {
        (0..<count).map { week in
            let start = sunday.addingTimeInterval(
                Double(week) * 7 * 86_400 + Double(weekday - 1) * 86_400 + Double(hour) * 3_600
            )
            return Trip(
                startedAt: start,
                endedAt: start.addingTimeInterval(minutes * 60),
                timezoneID: "UTC",
                points: [],
                destinationPlaceID: destination,
                variantID: variant,
                excludedFromStats: excluded
            )
        }
    }

    private func recommend(_ trips: [Trip], at context: RouteRecommender.Context? = nil) -> RouteRecommender.Recommendation? {
        RouteRecommender.recommend(variants: variants, trips: trips, context: context ?? tuesdayMorning)
    }

    // MARK: The ladder

    func testTheNarrowestTierAnswersWhenItHasFiveDrivesPerRoute() throws {
        let trips = drives(maple, count: 5, weekday: 3, hour: 9, minutes: 18)
            + drives(backWay, count: 5, weekday: 3, hour: 9, minutes: 22)
        let rec = try XCTUnwrap(recommend(trips))
        XCTAssertEqual(rec.tier, .weekdaySlot)
        XCTAssertEqual(rec.race.fastest?.id, maple)
        XCTAssertEqual(rec.drivesCounted, 10)
        guard case .winner = rec.race.outcome else { return XCTFail("expected a winner") }
    }

    /// Three Tuesday drives per route is two under tier 1's five; a
    /// single Wednesday each brings the weekday-morning tier to exactly
    /// its floor of four, and it answers there rather than widening
    /// further (D-071).
    func testItBacksOffOnlyAsFarAsTheFloorForces() throws {
        let trips = drives(maple, count: 3, weekday: 3, hour: 9, minutes: 18)
            + drives(backWay, count: 3, weekday: 3, hour: 9, minutes: 22)
            + drives(maple, count: 1, weekday: 4, hour: 10, minutes: 18)
            + drives(backWay, count: 1, weekday: 4, hour: 10, minutes: 22)
        let rec = try XCTUnwrap(recommend(trips))
        XCTAssertEqual(rec.tier, .dayClassSlot, "Tuesday alone was thin; weekday mornings were not")
        XCTAssertEqual(rec.race.fastest?.id, maple)
    }

    /// The ladder's signature case (D-071). Four drives per route, all on
    /// Tuesday mornings, is *not* a Tuesday-morning claim — tier 1 wants
    /// five — but it is a weekday-morning one, and that is what it says.
    /// The same history under D-070's flat four claimed the narrower
    /// sentence; under D-065's flat five it said nothing at all.
    func testFourTuesdayDrivesMakeAWeekdayClaimAndNotATuesdayOne() throws {
        let trips = drives(maple, count: 4, weekday: 3, hour: 9, minutes: 18)
            + drives(backWay, count: 4, weekday: 3, hour: 9, minutes: 22)
        let rec = try XCTUnwrap(recommend(trips))
        XCTAssertEqual(rec.tier, .dayClassSlot, "four is tier 2's floor, one short of tier 1's")
        XCTAssertEqual(rec.drivesCounted, 8)
        XCTAssertEqual(rec.race.fastest?.id, maple)
        guard case .winner = rec.race.outcome else { return XCTFail("four per route meets tier 2's floor") }
    }

    /// The ladder itself, stated once so a change to it is a change to a
    /// test: narrower claims earn a higher floor, and the two widest
    /// tiers sit on `RouteRaceEngine`'s own three.
    func testTheFloorsAreAFiveFourThreeThreeLadder() {
        let config = RouteRecommender.Config()
        XCTAssertEqual(config.floor(for: .weekdaySlot), 5)
        XCTAssertEqual(config.floor(for: .dayClassSlot), 4)
        XCTAssertEqual(config.floor(for: .slot), 3)
        XCTAssertEqual(config.floor(for: .all), 3)
        XCTAssertEqual(config.floor(for: .all), RouteRaceEngine.Config().minSamplesPerRoute,
                       "the widest tier makes the Destination screen's claim, so it uses its evidence")
    }

    /// Weekend drives do not count toward a weekday-morning claim, but do
    /// toward a this-slot-any-day one.
    func testWeekendDrivesFallOutsideTheDayClassTier() throws {
        let trips = drives(maple, count: 3, weekday: 3, hour: 9, minutes: 18)
            + drives(backWay, count: 3, weekday: 3, hour: 9, minutes: 22)
            + drives(maple, count: 2, weekday: 7, hour: 9, minutes: 18)
            + drives(backWay, count: 2, weekday: 7, hour: 9, minutes: 22)
        let rec = try XCTUnwrap(recommend(trips))
        XCTAssertEqual(rec.tier, .slot, "Saturdays are not weekday mornings, but they are mornings")
    }

    // MARK: Ties and floors

    /// A dead heat on Tuesday mornings is the finding. Other days that
    /// would decide it are not consulted.
    func testATieAtANarrowTierIsReportedNotWidened() throws {
        let trips = drives(maple, count: 5, weekday: 3, hour: 9, minutes: 18)
            + drives(backWay, count: 5, weekday: 3, hour: 9, minutes: 18.25)   // 15 s apart
            + drives(maple, count: 10, weekday: 5, hour: 9, minutes: 15)      // would win outright
            + drives(backWay, count: 10, weekday: 5, hour: 9, minutes: 25)
        let rec = try XCTUnwrap(recommend(trips))
        XCTAssertEqual(rec.tier, .weekdaySlot)
        guard case .tie = rec.race.outcome else { return XCTFail("a narrow tie must not be widened into a win") }
    }

    /// Three per route is under tiers 1 and 2 but meets tier 3's floor,
    /// so the claim widens to the time of day rather than going silent —
    /// and the Destination screen, on the same three drives, no longer
    /// calls a race the Plan tab refuses to (D-071).
    func testThreePerRouteWidensToTheTimeOfDayRatherThanGoingSilent() throws {
        let trips = drives(maple, count: 3, weekday: 3, hour: 9, minutes: 18)
            + drives(backWay, count: 3, weekday: 3, hour: 9, minutes: 22)
        let rec = try XCTUnwrap(recommend(trips))
        XCTAssertEqual(rec.tier, .slot)
        guard case .winner = rec.race.outcome else { return XCTFail("three per route meets tier 3's floor") }
    }

    /// Two per route is under every floor on the ladder, so nothing is
    /// claimed and the widest race comes back saying how much more it
    /// wants.
    func testUnderEveryFloorNothingIsClaimed() throws {
        let trips = drives(maple, count: 2, weekday: 3, hour: 9, minutes: 18)
            + drives(backWay, count: 2, weekday: 3, hour: 9, minutes: 22)
        let rec = try XCTUnwrap(recommend(trips), "routes exist, so the widest race comes back")
        XCTAssertEqual(rec.tier, .all)
        guard case let .collecting(needed) = rec.race.outcome else { return XCTFail("two is under every floor") }
        XCTAssertEqual(needed, 1)
        XCTAssertNil(rec.headline, "nothing to say until a floor is met")
    }

    /// Two real drives and three passenger rides is two drives, at every
    /// rung of the ladder including the lowest.
    func testExcludedDrivesNeverLiftARouteOverTheFloor() {
        let trips = drives(maple, count: 2, weekday: 3, hour: 9, minutes: 18)
            + drives(maple, count: 3, weekday: 3, hour: 9, minutes: 18, excluded: true)
            + drives(backWay, count: 5, weekday: 3, hour: 9, minutes: 22)
        guard let rec = recommend(trips) else { return }   // nil is also "no winner"
        if case .winner = rec.race.outcome { XCTFail("passenger rides cannot decide a route") }
    }

    func testNothingCountedIsNil() {
        XCTAssertNil(recommend([]))
    }

    // MARK: Context and words

    func testTheContextForNowLandsInTheCellATripWouldHave() {
        let tuesdayNineAM = sunday.addingTimeInterval(2 * 86_400 + 9 * 3_600)
        let context = RouteRecommender.Context(now: tuesdayNineAM, timezoneID: "UTC")
        XCTAssertEqual(context, tuesdayMorning)
        let trip = drives(maple, count: 1, weekday: 3, hour: 9, minutes: 18)[0]
        let cell = StatsEngine.cell(for: trip)
        XCTAssertEqual(cell.weekday, context.weekday)
        XCTAssertEqual(cell.bucket, context.bucket)
    }

    func testEachTierNamesItsOwnScope() {
        XCTAssertEqual(RouteRecommender.Tier.weekdaySlot.scope(for: tuesdayMorning), "on Tuesday mornings")
        XCTAssertEqual(RouteRecommender.Tier.dayClassSlot.scope(for: tuesdayMorning), "on weekday mornings")
        XCTAssertEqual(RouteRecommender.Tier.slot.scope(for: tuesdayMorning), "at this time of day")
        XCTAssertEqual(RouteRecommender.Tier.all.scope(for: tuesdayMorning), "")
        let saturdayEvening = RouteRecommender.Context(weekday: 7, bucket: 4)
        XCTAssertEqual(RouteRecommender.Tier.dayClassSlot.scope(for: saturdayEvening), "on weekend evenings")
    }

    func testTheHeadlineSaysTheWinnerOrTheTieAndTheScope() throws {
        let winner = try XCTUnwrap(recommend(
            drives(maple, count: 5, weekday: 3, hour: 9, minutes: 18)
                + drives(backWay, count: 5, weekday: 3, hour: 9, minutes: 22)
        ))
        XCTAssertEqual(winner.headline, "via Maple Ave is usually fastest on Tuesday mornings")

        let tie = try XCTUnwrap(recommend(
            drives(maple, count: 5, weekday: 3, hour: 9, minutes: 18)
                + drives(backWay, count: 5, weekday: 3, hour: 9, minutes: 18.25)
        ))
        XCTAssertEqual(tie.headline, "No clear winner on Tuesday mornings")
    }
}
