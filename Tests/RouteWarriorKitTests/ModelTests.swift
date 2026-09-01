import Foundation
import Testing
@testable import RouteWarriorKit

struct ModelTests {
    @Test func placeGeofenceContainment() {
        let place = Place(
            name: "Home",
            coordinate: Coordinate(latitude: 0, longitude: 0),
            radiusM: 75
        )
        // 0.0005° of latitude ≈ 55.6 m: inside. 0.001° ≈ 111.2 m: outside.
        #expect(place.contains(Coordinate(latitude: 0.0005, longitude: 0)))
        #expect(!place.contains(Coordinate(latitude: 0.001, longitude: 0)))
    }

    @Test func tripDurationIsEndMinusStart() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trip = Trip(
            startedAt: start,
            endedAt: start.addingTimeInterval(1_260),
            timezoneID: "America/Chicago",
            points: []
        )
        #expect(trip.duration == 1_260)
    }

    @Test func snapshotTrafficFactor() {
        let snapshot = PlanSnapshot(
            requestedAt: .now,
            polyline: Polyline(coordinates: []),
            distanceM: 10_000,
            staticDuration: 600,
            trafficDuration: 780
        )
        #expect(abs(snapshot.trafficFactor - 1.3) < 0.0001)

        let degenerate = PlanSnapshot(
            requestedAt: .now,
            polyline: Polyline(coordinates: []),
            distanceM: 0,
            staticDuration: 0,
            trafficDuration: 0
        )
        #expect(degenerate.trafficFactor == 1)
    }

    @Test func tripSurvivesCodableRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trip = Trip(
            startedAt: start,
            endedAt: start.addingTimeInterval(900),
            timezoneID: "America/Chicago",
            points: [
                TrackPoint(
                    coordinate: Coordinate(latitude: 41.9, longitude: -87.6),
                    timestamp: start,
                    speedMps: 12.5,
                    courseDegrees: 270,
                    horizontalAccuracyM: 5
                ),
            ],
            originPlaceID: UUID(),
            destinationPlaceID: UUID(),
            distanceM: 8_400,
            movingTime: 780,
            idleTime: 120,
            stopEvents: [
                StopEvent(
                    coordinate: Coordinate(latitude: 41.91, longitude: -87.61),
                    startedAt: start.addingTimeInterval(300),
                    duration: 24,
                    cause: .signal,
                    matchedOSMNode: 123_456_789
                ),
            ],
            snapshotID: UUID(),
            followedPlan: false,
            source: .manual,
            excludedFromStats: false
        )
        let decoded = try JSONDecoder().decode(Trip.self, from: JSONEncoder().encode(trip))
        #expect(decoded == trip)
    }

    @Test func variantSurvivesCodableRoundTrip() throws {
        let variant = RouteVariant(
            originPlaceID: UUID(),
            destinationPlaceID: UUID(),
            representativePolyline: Polyline(coordinates: [
                Coordinate(latitude: 41.9, longitude: -87.6),
                Coordinate(latitude: 41.95, longitude: -87.65),
            ]),
            autoName: "via Maple Ave",
            tripCount: 3,
            intersections: IntersectionInventory(
                signalCount: 7,
                stopSignCount: 2,
                coverageConfidence: .medium,
                fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        let decoded = try JSONDecoder().decode(RouteVariant.self, from: JSONEncoder().encode(variant))
        #expect(decoded == variant)
    }
}
