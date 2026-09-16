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

    /// Three Tuesday drives per route is one under the floor; a single
    /// Wednesday each brings the weekday-morning tier to exactly four,
    /// and it answers there rather than widening further (D-070).
    func testItBacksOffOnlyAsFarAsTheFloorForces() throws {
        let trips = drives(maple, count: 3, weekday: 3, hour: 9, minutes: 18)
            + drives(backWay, count: 3, weekday: 3, hour: 9, minutes: 22)
            + drives(maple, count: 1, weekday: 4, hour: 10, minutes: 18)
            + drives(backWay, count: 1, weekday: 4, hour: 10, minutes: 22)
        let rec = try XCTUnwrap(recommend(trips))
        XCTAssertEqual(rec.tier, .dayClassSlot, "Tuesday alone was thin; weekday mornings were not")
        XCTAssertEqual(rec.race.fastest?.id, maple)
    }

    /// The floor is met exactly, at the narrowest tier: four drives per
    /// route on Tuesday mornings is a Tuesday-morning claim (D-070). Under
    /// D-065's flat five this same history said nothing at all.
    func testFourDrivesPerRouteIsEnoughForTheNarrowestClaim() throws {
        let trips = drives(maple, count: 4, weekday: 3, hour: 9, minutes: 18)
            + drives(backWay, count: 4, weekday: 3, hour: 9, minutes: 22)
        let rec = try XCTUnwrap(recommend(trips))
        XCTAssertEqual(rec.tier, .weekdaySlot)
        XCTAssertEqual(rec.drivesCounted, 8)
        XCTAssertEqual(rec.race.fastest?.id, maple)
        guard case .winner = rec.race.outcome else { return XCTFail("four per route meets the floor") }
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

    /// Three per route is under the floor everywhere, including the
    /// widest tier — where the Destination screen's all-time race, which
    /// keeps `RouteRaceEngine`'s floor of three, would call it. The two
    /// surfaces answer different questions and are allowed to disagree
    /// about when there is enough history (D-070).
    func testTheFloorIsFourPerRouteAtEveryTier() throws {
        let trips = drives(maple, count: 3, weekday: 3, hour: 9, minutes: 18)
            + drives(backWay, count: 3, weekday: 3, hour: 9, minutes: 22)
        let rec = try XCTUnwrap(recommend(trips), "routes exist, so the widest race comes back")
        XCTAssertEqual(rec.tier, .all)
        guard case let .collecting(needed) = rec.race.outcome else { return XCTFail("three is under the floor") }
        XCTAssertEqual(needed, 1)
        XCTAssertNil(rec.headline, "nothing to say until the floor is met")
    }

    func testExcludedDrivesNeverLiftARouteOverTheFloor() {
        let trips = drives(maple, count: 3, weekday: 3, hour: 9, minutes: 18)
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
