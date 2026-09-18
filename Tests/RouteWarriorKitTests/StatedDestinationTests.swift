import Foundation
import Testing
@testable import RouteWarriorKit

/// D-081: a drive ends at its last *moving* point, and a place's fence is
/// 75 m, so a car park, a garage or a slow crawl to the door all end a
/// drive outside the fence of the place it plainly reached — and the trip
/// finished with no destination at all. A destination the driver named
/// was used to buy a plan and nothing else, so even saying where you were
/// going did not help.
///
/// Along the equator, 0.00001° of longitude ≈ 1.11 m, which is how these
/// distances are built.
struct StatedDestinationTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let home = Place(name: "Home", coordinate: Coordinate(latitude: 0, longitude: 0))
    private let school = Place(name: "School", coordinate: Coordinate(latitude: 0, longitude: 0.09))
    private var places: [Place] { [home, school] }

    /// Metres east of the school, as a coordinate.
    private func shortOfSchool(byMetres metres: Double) -> Coordinate {
        Coordinate(latitude: 0, longitude: 0.09 - metres / 111_320)
    }

    private func trip(endingAt end: Coordinate) -> Trip {
        let points = [
            TrackPoint(coordinate: Coordinate(latitude: 0, longitude: 0), timestamp: t0,
                       speedMps: 11, horizontalAccuracyM: 5),
            TrackPoint(coordinate: Coordinate(latitude: 0, longitude: 0.045),
                       timestamp: t0.addingTimeInterval(300), speedMps: 11, horizontalAccuracyM: 5),
            TrackPoint(coordinate: end, timestamp: t0.addingTimeInterval(600),
                       speedMps: 11, horizontalAccuracyM: 5),
        ]
        return Trip(
            startedAt: points.first!.timestamp,
            endedAt: points.last!.timestamp,
            timezoneID: "America/Chicago",
            points: points
        )
    }

    // MARK: Inside the fence still wins

    @Test func aPointInsideAFenceBelongsToThatPlaceAsBefore() {
        let result = RouteMatcher.assign(
            trip: trip(endingAt: shortOfSchool(byMetres: 20)), places: places, variants: []
        )
        #expect(result.trip.destinationPlaceID == school.id)
    }

    // MARK: Just outside it

    @Test func aDriveEndingJustOutsideTheFenceStillReachedThePlace() {
        // 120 m short: outside the 75 m fence, inside the 200 m tolerance.
        let result = RouteMatcher.assign(
            trip: trip(endingAt: shortOfSchool(byMetres: 120)), places: places, variants: []
        )
        #expect(result.trip.destinationPlaceID == school.id)
    }

    @Test func aDriveEndingWellAwayFromEverythingNamesNoPlace() {
        let result = RouteMatcher.assign(
            trip: trip(endingAt: shortOfSchool(byMetres: 900)), places: places, variants: []
        )
        #expect(result.trip.destinationPlaceID == nil)
    }

    /// The tolerance must not let a place two streets away claim a drive
    /// that ended nearer another.
    @Test func theNearestPlaceWinsRatherThanTheFirstInTheList() {
        // The shop sits 150 m short of the school with a 10 m fence; the
        // drive ends 120 m short. Outside *both* fences, so this is the
        // fallback deciding — 30 m from the shop, 120 m from the school.
        let shop = Place(
            name: "The shop", coordinate: shortOfSchool(byMetres: 150), radiusM: 10
        )
        let result = RouteMatcher.assign(
            trip: trip(endingAt: shortOfSchool(byMetres: 120)),
            places: [school, shop], variants: []
        )
        #expect(result.trip.destinationPlaceID == shop.id)
    }

    // MARK: What the driver said

    @Test func aNamedDestinationIsUsedWhenTheTrackCannotNameOne() {
        // 400 m short: past the endpoint tolerance, inside the stated one.
        let result = RouteMatcher.assign(
            trip: trip(endingAt: shortOfSchool(byMetres: 400)), places: places, variants: [],
            statedDestinationID: school.id
        )
        #expect(result.trip.destinationPlaceID == school.id)
    }

    /// Saying "home" and then driving somewhere else makes the statement
    /// wrong, not the drive. Past the stated tolerance the trip keeps no
    /// destination rather than an untrue one.
    @Test func aNamedDestinationTheDriveNeverReachedIsNotHonoured() {
        let result = RouteMatcher.assign(
            trip: trip(endingAt: shortOfSchool(byMetres: 5_000)), places: places, variants: [],
            statedDestinationID: school.id
        )
        #expect(result.trip.destinationPlaceID == nil)
    }

    /// Where the drive actually ended outranks what the driver said
    /// about it beforehand.
    @Test func whereTheDriveEndedOutranksWhatWasSaid() {
        let result = RouteMatcher.assign(
            trip: trip(endingAt: shortOfSchool(byMetres: 20)), places: places, variants: [],
            statedDestinationID: home.id
        )
        #expect(result.trip.destinationPlaceID == school.id)
    }

    @Test func aNamedPlaceThatNoLongerExistsNamesNothing() {
        let result = RouteMatcher.assign(
            trip: trip(endingAt: shortOfSchool(byMetres: 400)), places: places, variants: [],
            statedDestinationID: UUID()
        )
        #expect(result.trip.destinationPlaceID == nil)
    }

    // MARK: The start of the drive gets the same benefit

    @Test func aDriveBeginningJustOutsideAFenceStillStartedThere() {
        let points = [
            TrackPoint(coordinate: Coordinate(latitude: 0, longitude: 120 / 111_320),
                       timestamp: t0, speedMps: 11, horizontalAccuracyM: 5),
            TrackPoint(coordinate: Coordinate(latitude: 0, longitude: 0.045),
                       timestamp: t0.addingTimeInterval(300), speedMps: 11, horizontalAccuracyM: 5),
            TrackPoint(coordinate: Coordinate(latitude: 0, longitude: 0.09),
                       timestamp: t0.addingTimeInterval(600), speedMps: 11, horizontalAccuracyM: 5),
        ]
        let drive = Trip(
            startedAt: points.first!.timestamp, endedAt: points.last!.timestamp,
            timezoneID: "America/Chicago", points: points
        )
        let result = RouteMatcher.assign(trip: drive, places: places, variants: [])
        #expect(result.trip.originPlaceID == home.id)
        // Both ends known means the drive can found a route (D-029).
        #expect(result.newVariant != nil)
    }
}
