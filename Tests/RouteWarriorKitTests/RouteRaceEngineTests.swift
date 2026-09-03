import Foundation
import XCTest

@testable import RouteWarriorKit

/// "Which of my own ways to school is faster?" — the question the
/// destination screen answers from a driver's own history.
final class RouteRaceEngineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let origin = UUID()
    private let destination = UUID()
    private let backWay = UUID()
    private let highway = UUID()
    private let line = Polyline(coordinates: [
        Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 0.01),
    ])

    private func variant(_ id: UUID, named: String = "", signals: Int? = nil, stops: Int? = nil) -> RouteVariant {
        var inventory: IntersectionInventory?
        if let signals, let stops {
            inventory = IntersectionInventory(
                signalCount: signals, stopSignCount: stops, coverageConfidence: .high, fetchedAt: t0
            )
        }
        return RouteVariant(
            id: id,
            originPlaceID: origin,
            destinationPlaceID: destination,
            representativePolyline: line,
            autoName: named,
            intersections: inventory
        )
    }

    /// `count` drives on `variantID`, each `minutes` long.
    private func drives(_ variantID: UUID, count: Int, minutes: Double, excluded: Bool = false) -> [Trip] {
        (0..<count).map { index in
            let start = t0.addingTimeInterval(Double(index) * 86_400)
            return Trip(
                startedAt: start,
                endedAt: start.addingTimeInterval(minutes * 60),
                timezoneID: "UTC",
                points: [],
                destinationPlaceID: destination,
                variantID: variantID,
                excludedFromStats: excluded
            )
        }
    }

    func testOneRouteHasNothingToRaceAgainst() {
        let race = RouteRaceEngine.race(
            variants: [variant(backWay)],
            trips: drives(backWay, count: 9, minutes: 10)
        )
        XCTAssertEqual(race.outcome, .oneRouteOnly)
        XCTAssertEqual(race.routes.count, 1)
        XCTAssertNil(race.runnerUp)
    }

    func testTwoRoutesShortOfTheFloorAreStillCollecting() {
        let race = RouteRaceEngine.race(
            variants: [variant(backWay), variant(highway)],
            trips: drives(backWay, count: 3, minutes: 10) + drives(highway, count: 1, minutes: 20)
        )
        XCTAssertEqual(race.outcome, .collecting(drivesNeeded: 2))
    }

    func testAClearWinnerIsCalledWithItsGap() {
        let race = RouteRaceEngine.race(
            variants: [variant(highway, named: "via the highway"), variant(backWay, named: "the back way")],
            trips: drives(backWay, count: 4, minutes: 10) + drives(highway, count: 5, minutes: 14)
        )
        XCTAssertEqual(race.outcome, .winner(gapSeconds: 240, confidence: .medium))
        XCTAssertEqual(race.fastest?.name, "the back way")
        XCTAssertEqual(race.runnerUp?.name, "via the highway")
    }

    func testEnoughDrivesOnBothSidesRaisesConfidence() {
        let race = RouteRaceEngine.race(
            variants: [variant(backWay), variant(highway)],
            trips: drives(backWay, count: 8, minutes: 10) + drives(highway, count: 8, minutes: 14)
        )
        XCTAssertEqual(race.outcome, .winner(gapSeconds: 240, confidence: .high))
    }

    func testRoutesInsideTheMarginAreATieNotAWin() {
        let race = RouteRaceEngine.race(
            variants: [variant(backWay), variant(highway)],
            trips: drives(backWay, count: 3, minutes: 10) + drives(highway, count: 3, minutes: 10.25)
        )
        // 15 seconds apart: the same drive on a different day.
        XCTAssertEqual(race.outcome, .tie(gapSeconds: 15))
    }

    func testRoutesAreRankedFastestFirst() {
        let scenic = UUID()
        let race = RouteRaceEngine.race(
            variants: [variant(highway, named: "highway"), variant(scenic, named: "scenic"), variant(backWay, named: "back")],
            trips: drives(highway, count: 3, minutes: 14)
                + drives(scenic, count: 3, minutes: 20)
                + drives(backWay, count: 3, minutes: 10)
        )
        XCTAssertEqual(race.routes.map(\.name), ["back", "highway", "scenic"])
    }

    func testPassengerRidesCannotDecideARoute() {
        // Three drives, but two were as a passenger: below the floor.
        let race = RouteRaceEngine.race(
            variants: [variant(backWay), variant(highway)],
            trips: drives(backWay, count: 1, minutes: 10)
                + drives(backWay, count: 2, minutes: 30, excluded: true)
                + drives(highway, count: 3, minutes: 14)
        )
        XCTAssertEqual(race.outcome, .collecting(drivesNeeded: 2))
        // And the excluded rides did not drag its median towards 30.
        XCTAssertEqual(race.routes.first { $0.id == backWay }?.stats.median, 600)
    }

    func testARouteWithNoDrivesIsNotInTheRace() {
        let neverDriven = UUID()
        let race = RouteRaceEngine.race(
            variants: [variant(backWay), variant(highway), variant(neverDriven)],
            trips: drives(backWay, count: 3, minutes: 10) + drives(highway, count: 3, minutes: 14)
        )
        XCTAssertEqual(race.routes.count, 2)
        XCTAssertNil(race.routes.first { $0.id == neverDriven })
    }

    func testIntersectionsSumOnlyOnceBothCountsAreKnown() {
        let race = RouteRaceEngine.race(
            variants: [variant(backWay, signals: 2, stops: 5), variant(highway)],
            trips: drives(backWay, count: 3, minutes: 10) + drives(highway, count: 3, minutes: 14)
        )
        XCTAssertEqual(race.routes.first { $0.id == backWay }?.intersectionCount, 7)
        XCTAssertNil(race.routes.first { $0.id == highway }?.intersectionCount)
    }

    func testTheDriversOwnNameWinsOverTheGeneratedOne() {
        var named = variant(backWay, named: "via Maple Ave")
        named.customName = "the back way"
        let race = RouteRaceEngine.race(
            variants: [named, variant(highway)],
            trips: drives(backWay, count: 3, minutes: 10) + drives(highway, count: 3, minutes: 14)
        )
        XCTAssertEqual(race.fastest?.name, "the back way")
        XCTAssertEqual(race.runnerUp?.name, "Route")
    }
}
