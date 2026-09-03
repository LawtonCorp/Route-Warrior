import Foundation
import XCTest

@testable import RouteWarrior

/// What the Trips tab shows and in what order (D-026). The organizer is
/// pure, so every rule is checked here rather than by eye on a phone.
final class TripOrganizerTests: XCTestCase {
    private struct Stub: TripSortable {
        var id = UUID()
        var startedAt: Date
        var endedAt: Date
        var distanceM: Double = 1_000
        var destinationPlaceID: UUID?
        var excludedFromStats = false
        var delta: Double?
    }

    /// Noon UTC on a fixed day, in a fixed calendar, so "today" never
    /// depends on when the suite runs.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_756_900_800)

    private func at(_ offsetHours: Double, minutes: Double = 60, km: Double = 1, delta: Double? = nil) -> Stub {
        let start = now.addingTimeInterval(offsetHours * 3_600)
        return Stub(
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            distanceM: km * 1_000,
            delta: delta
        )
    }

    private func arrange(_ organizer: TripOrganizer, _ trips: [Stub]) -> (today: [Stub], earlier: [Stub]) {
        organizer.arrange(trips, delta: { $0.delta }, now: now, calendar: calendar)
    }

    func testTodayIsSplitOffTheTop() {
        let thisMorning = at(-3)
        let lastNight = at(-20)
        let lastWeek = at(-24 * 7)
        let result = arrange(TripOrganizer(), [lastWeek, lastNight, thisMorning])

        XCTAssertEqual(result.today.map(\.id), [thisMorning.id])
        XCTAssertEqual(result.earlier.map(\.id), [lastNight.id, lastWeek.id])
    }

    func testNewestAndOldestAreMirrorImages() {
        let trips = [at(-24 * 3), at(-24 * 1), at(-24 * 2)]
        let newest = arrange(TripOrganizer(sort: .newest), trips).earlier
        let oldest = arrange(TripOrganizer(sort: .oldest), trips).earlier

        XCTAssertEqual(newest.map(\.startedAt), newest.map(\.startedAt).sorted(by: >))
        XCTAssertEqual(oldest.map(\.id), newest.reversed().map(\.id))
    }

    func testLongestAndFarthestRankOnTheirOwnMeasure() {
        let quickButFar = at(-24, minutes: 10, km: 90)
        let slowButNear = at(-48, minutes: 120, km: 2)
        let trips = [quickButFar, slowButNear]

        XCTAssertEqual(arrange(TripOrganizer(sort: .longest), trips).earlier.map(\.id), [slowButNear.id, quickButFar.id])
        XCTAssertEqual(arrange(TripOrganizer(sort: .farthest), trips).earlier.map(\.id), [quickButFar.id, slowButNear.id])
    }

    func testBiggestWinRanksTheMostNegativeDeltaFirstAndSinksTheUncompared() {
        let bigWin = at(-24, delta: -300)
        let smallWin = at(-48, delta: -30)
        let loss = at(-72, delta: 120)
        let noComparison = at(-96, delta: nil)
        let result = arrange(TripOrganizer(sort: .biggestWin), [noComparison, loss, smallWin, bigWin])

        XCTAssertEqual(result.earlier.map(\.id), [bigWin.id, smallWin.id, loss.id, noComparison.id])
    }

    func testOutcomeFiltersSplitWinnersFromLosers() {
        let win = at(-24, delta: -10)
        let loss = at(-48, delta: 10)
        let noComparison = at(-72, delta: nil)
        let trips = [win, loss, noComparison]

        XCTAssertEqual(arrange(TripOrganizer(outcome: .beat), trips).earlier.map(\.id), [win.id])
        XCTAssertEqual(arrange(TripOrganizer(outcome: .lost), trips).earlier.map(\.id), [loss.id])
        // A trip with no ETA to beat belongs to neither side.
        XCTAssertEqual(arrange(TripOrganizer(outcome: .any), trips).earlier.count, 3)
    }

    func testExcludedFilterFindsOnlyThePassengerRides() {
        var passenger = at(-24)
        passenger.excludedFromStats = true
        let driven = at(-48)

        XCTAssertEqual(arrange(TripOrganizer(outcome: .excluded), [driven, passenger]).earlier.map(\.id), [passenger.id])
    }

    func testDestinationFilterKeepsOnlyThatPlace() {
        let home = UUID()
        var toHome = at(-24)
        toHome.destinationPlaceID = home
        var toWork = at(-48)
        toWork.destinationPlaceID = UUID()
        let unmatched = at(-72)

        let result = arrange(TripOrganizer(destination: home), [toHome, toWork, unmatched])
        XCTAssertEqual(result.earlier.map(\.id), [toHome.id])
    }

    func testFiltersAndSortCombine() {
        let home = UUID()
        var slowHome = at(-24, minutes: 90, delta: -10)
        slowHome.destinationPlaceID = home
        var quickHome = at(-48, minutes: 20, delta: -10)
        quickHome.destinationPlaceID = home
        var lostHome = at(-72, minutes: 200, delta: 500)
        lostHome.destinationPlaceID = home
        var elsewhere = at(-96, minutes: 300, delta: -10)
        elsewhere.destinationPlaceID = UUID()

        let result = arrange(
            TripOrganizer(sort: .longest, destination: home, outcome: .beat),
            [quickHome, elsewhere, lostHome, slowHome]
        )
        XCTAssertEqual(result.earlier.map(\.id), [slowHome.id, quickHome.id])
    }

    func testTiesKeepAStableOrder() {
        let start = now.addingTimeInterval(-24 * 3_600)
        let a = Stub(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!, startedAt: start, endedAt: start)
        let b = Stub(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!, startedAt: start, endedAt: start)

        XCTAssertEqual(arrange(TripOrganizer(), [b, a]).earlier.map(\.id), [a.id, b.id])
        XCTAssertEqual(arrange(TripOrganizer(), [a, b]).earlier.map(\.id), [a.id, b.id])
    }
}
