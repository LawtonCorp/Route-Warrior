import Foundation
import Testing
@testable import RouteWarriorKit

/// Two hand-built ways from home to school along the equator: Route A runs
/// straight; Route B arcs ~1.1 km north for most of the way. Expected
/// deviations follow from the constructed geometry (0.001° of latitude ≈
/// 111 m), independent of the matcher.
struct RouteMatcherTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let home = Place(name: "Home", coordinate: Coordinate(latitude: 0, longitude: 0))
    private let school = Place(name: "School", coordinate: Coordinate(latitude: 0, longitude: 0.09))
    private var places: [Place] { [home, school] }

    /// Samples corner-defined shapes into ~110 m-spaced points.
    private func trackPoints(via corners: [Coordinate]) -> [TrackPoint] {
        let line = Polyline(coordinates: corners).resampled(to: 91)
        return line.coordinates.enumerated().map { i, c in
            TrackPoint(
                coordinate: c,
                timestamp: t0.addingTimeInterval(Double(i) * 10),
                speedMps: 11,
                horizontalAccuracyM: 5
            )
        }
    }

    private var straightRoute: [Coordinate] {
        [Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 0.09)]
    }

    private var northernArc: [Coordinate] {
        [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0.01, longitude: 0.01),
            Coordinate(latitude: 0.01, longitude: 0.08),
            Coordinate(latitude: 0, longitude: 0.09),
        ]
    }

    private func trip(via corners: [Coordinate]) -> Trip {
        let points = trackPoints(via: corners)
        return Trip(
            startedAt: points.first!.timestamp,
            endedAt: points.last!.timestamp,
            timezoneID: "America/Chicago",
            points: points
        )
    }

    @Test func assignsEndpointPlaces() {
        let result = RouteMatcher.assign(trip: trip(via: straightRoute), places: places, variants: [])
        #expect(result.trip.originPlaceID == home.id)
        #expect(result.trip.destinationPlaceID == school.id)
    }

    @Test func firstTripFoundsAVariant() {
        let result = RouteMatcher.assign(trip: trip(via: straightRoute), places: places, variants: [])
        #expect(result.newVariant != nil)
        #expect(result.trip.variantID == result.newVariant?.id)
        #expect(result.newVariant?.autoName == "Route A")
        #expect(result.newVariant?.originPlaceID == home.id)
        #expect(result.newVariant?.destinationPlaceID == school.id)
        #expect(result.newVariant?.representativePolyline.coordinates.count == 64)
    }

    @Test func similarTripJoinsTheExistingVariant() {
        let founding = RouteMatcher.assign(trip: trip(via: straightRoute), places: places, variants: [])
        let variant = founding.newVariant!

        // ~33 m north of Route A the whole way: same route, GPS-level noise.
        let jittered = trip(via: [
            Coordinate(latitude: 0.0003, longitude: 0),
            Coordinate(latitude: 0.0003, longitude: 0.09),
        ])
        let result = RouteMatcher.assign(trip: jittered, places: places, variants: [variant])
        #expect(result.newVariant == nil)
        #expect(result.variantID == variant.id)
        #expect(result.trip.variantID == variant.id)
    }

    @Test func differentShapeFoundsASecondVariant() {
        let founding = RouteMatcher.assign(trip: trip(via: straightRoute), places: places, variants: [])
        let variantA = founding.newVariant!

        let result = RouteMatcher.assign(trip: trip(via: northernArc), places: places, variants: [variantA])
        #expect(result.newVariant != nil)
        #expect(result.newVariant?.id != variantA.id)
        #expect(result.newVariant?.autoName == "Route B")
    }

    @Test func picksTheCloserOfTwoVariants() {
        let a = RouteMatcher.assign(trip: trip(via: straightRoute), places: places, variants: []).newVariant!
        let b = RouteMatcher.assign(trip: trip(via: northernArc), places: places, variants: [a]).newVariant!

        let nearArc = trip(via: [
            Coordinate(latitude: 0.0003, longitude: 0),
            Coordinate(latitude: 0.0103, longitude: 0.01),
            Coordinate(latitude: 0.0103, longitude: 0.08),
            Coordinate(latitude: 0.0003, longitude: 0.09),
        ])
        let result = RouteMatcher.assign(trip: nearArc, places: places, variants: [a, b])
        #expect(result.variantID == b.id)
        #expect(result.newVariant == nil)
    }

    @Test func noDestinationPlaceMeansNoVariant() {
        // Ends in the middle of nowhere: 0.045° ≈ 5 km from either place.
        let wander = trip(via: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 0.045),
        ])
        let result = RouteMatcher.assign(trip: wander, places: places, variants: [])
        #expect(result.trip.originPlaceID == home.id)
        #expect(result.trip.destinationPlaceID == nil)
        #expect(result.variantID == nil)
        #expect(result.newVariant == nil)
    }

    @Test func followedPlanLabeling() {
        let snapshot = PlanSnapshot(
            requestedAt: t0,
            polyline: Polyline(coordinates: straightRoute),
            distanceM: 10_000,
            staticDuration: 600,
            trafficDuration: 700
        )
        let followed = RouteMatcher.assign(
            trip: trip(via: straightRoute), places: places, variants: [], snapshot: snapshot
        )
        #expect(followed.trip.followedPlan == true)

        let deviated = RouteMatcher.assign(
            trip: trip(via: northernArc), places: places, variants: [], snapshot: snapshot
        )
        #expect(deviated.trip.followedPlan == false)

        let unlabeled = RouteMatcher.assign(trip: trip(via: straightRoute), places: places, variants: [])
        #expect(unlabeled.trip.followedPlan == nil)
    }

    @Test func autoNamesRunThroughTheAlphabetThenNumber() {
        #expect(RouteMatcher.nextAutoName(after: 0) == "Route A")
        #expect(RouteMatcher.nextAutoName(after: 1) == "Route B")
        #expect(RouteMatcher.nextAutoName(after: 25) == "Route Z")
        #expect(RouteMatcher.nextAutoName(after: 26) == "Route A2")
    }
}
