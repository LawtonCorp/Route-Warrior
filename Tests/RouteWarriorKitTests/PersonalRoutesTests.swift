import Foundation
import XCTest

@testable import RouteWarriorKit

/// D-066: the driver's own routes as rows — every route with a drive, the
/// number from the tier that answered, the claim on the top row only.
final class PersonalRoutesTests: XCTestCase {
    private let sunday = Date(timeIntervalSince1970: 1_699_747_200)
    private let origin = UUID()
    private let destination = UUID()
    private let maple = UUID()
    private let backWay = UUID()
    private let weekendOnly = UUID()
    private let tuesdayMorning = RouteRecommender.Context(weekday: 3, bucket: 2)

    private func line(_ east: Double) -> Polyline {
        Polyline(coordinates: [Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: east)])
    }

    private var variants: [RouteVariant] {
        [
            RouteVariant(id: maple, originPlaceID: origin, destinationPlaceID: destination,
                         representativePolyline: line(0.01), autoName: "via Maple Ave"),
            RouteVariant(id: backWay, originPlaceID: origin, destinationPlaceID: destination,
                         representativePolyline: line(0.02), autoName: "the back way"),
            RouteVariant(id: weekendOnly, originPlaceID: origin, destinationPlaceID: destination,
                         representativePolyline: line(0.03), autoName: "the scenic way"),
        ]
    }

    private func drives(_ variant: UUID, count: Int, weekday: Int, hour: Int, minutes: Double) -> [Trip] {
        (0..<count).map { week in
            let start = sunday.addingTimeInterval(
                Double(week) * 7 * 86_400 + Double(weekday - 1) * 86_400 + Double(hour) * 3_600
            )
            return Trip(
                startedAt: start, endedAt: start.addingTimeInterval(minutes * 60), timezoneID: "UTC",
                points: [], destinationPlaceID: destination, variantID: variant
            )
        }
    }

    func testEveryRouteWithADriveIsARowAndTheTopOneCarriesTheClaim() {
        let trips = drives(maple, count: 5, weekday: 3, hour: 9, minutes: 18)
            + drives(backWay, count: 5, weekday: 3, hour: 9, minutes: 22)
            + drives(weekendOnly, count: 2, weekday: 7, hour: 9, minutes: 30)
        let rows = PersonalRoutes.rows(variants: variants, trips: trips, context: tuesdayMorning)

        XCTAssertEqual(rows.map(\.id), [maple, backWay, weekendOnly], "recommendation order, then the rest")
        XCTAssertEqual(rows[0].claim, "usually fastest on Tuesday mornings")
        XCTAssertNil(rows[1].claim)
        XCTAssertNil(rows[2].claim)
        XCTAssertEqual(rows[0].polyline, line(0.01), "the row carries the line the map will draw")
    }

    /// A route the answering tier never saw is still offered — the driver
    /// may want it — but numbered from every drive and labelled so.
    func testARouteOutsideTheTierIsNumberedFromAllDrives() {
        let trips = drives(maple, count: 5, weekday: 3, hour: 9, minutes: 18)
            + drives(backWay, count: 5, weekday: 3, hour: 9, minutes: 22)
            + drives(weekendOnly, count: 2, weekday: 7, hour: 9, minutes: 30)
        let rows = PersonalRoutes.rows(variants: variants, trips: trips, context: tuesdayMorning)
        let scenic = rows.first { $0.id == weekendOnly }!
        XCTAssertEqual(scenic.tier, .all)
        XCTAssertEqual(scenic.usualDuration, 1_800)
        XCTAssertEqual(scenic.drivesCounted, 2)
        XCTAssertEqual(rows[0].tier, .weekdaySlot)
        XCTAssertEqual(rows[0].drivesCounted, 5)
    }

    func testATieIsSaidOnTheTopRow() {
        let trips = drives(maple, count: 5, weekday: 3, hour: 9, minutes: 18)
            + drives(backWay, count: 5, weekday: 3, hour: 9, minutes: 18.25)
        let rows = PersonalRoutes.rows(variants: variants, trips: trips, context: tuesdayMorning)
        XCTAssertEqual(rows[0].claim, "no clear winner on Tuesday mornings")
        XCTAssertNil(rows[1].claim)
    }

    /// Under the floor at every tier there is no claim, but the rows are
    /// still there to pick from, numbered from every drive.
    func testUnderTheFloorThereAreRowsButNoClaim() {
        let trips = drives(maple, count: 2, weekday: 3, hour: 9, minutes: 18)
            + drives(backWay, count: 2, weekday: 3, hour: 9, minutes: 22)
        let rows = PersonalRoutes.rows(variants: variants, trips: trips, context: tuesdayMorning)
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.claim == nil })
        XCTAssertTrue(rows.allSatisfy { $0.tier == .all })
    }

    func testNoDrivesMeansNoRows() {
        XCTAssertEqual(PersonalRoutes.rows(variants: variants, trips: [], context: tuesdayMorning), [])
    }
}
