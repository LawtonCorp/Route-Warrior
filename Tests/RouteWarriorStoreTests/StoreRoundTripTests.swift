import Foundation
import RouteWarriorKit
import SwiftData
import Testing
@testable import RouteWarriorStore

/// Every kit value must survive record round-trips bit-for-bit — except
/// polylines, stored in E5 encoding, whose coordinates are constructed at
/// 1e-5 precision here so equality is exact.
struct StoreRoundTripTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeTrip() -> Trip {
        Trip(
            startedAt: t0,
            endedAt: t0.addingTimeInterval(900),
            timezoneID: "America/Chicago",
            points: [
                TrackPoint(
                    coordinate: Coordinate(latitude: 41.9, longitude: -87.6),
                    timestamp: t0,
                    speedMps: 12.5,
                    courseDegrees: 270,
                    horizontalAccuracyM: 5
                ),
                TrackPoint(
                    coordinate: Coordinate(latitude: 41.91, longitude: -87.61),
                    timestamp: t0.addingTimeInterval(60),
                    speedMps: 14,
                    courseDegrees: 265,
                    horizontalAccuracyM: 4
                ),
            ],
            originPlaceID: UUID(),
            destinationPlaceID: UUID(),
            variantID: UUID(),
            distanceM: 8_400,
            movingTime: 780,
            idleTime: 120,
            stopEvents: [
                StopEvent(
                    coordinate: Coordinate(latitude: 41.905, longitude: -87.605),
                    startedAt: t0.addingTimeInterval(300),
                    duration: 24,
                    cause: .signal,
                    matchedOSMNode: 42
                ),
            ],
            snapshotID: UUID(),
            followedPlan: false,
            source: .manual,
            excludedFromStats: true
        )
    }

    @Test func tripRecordRoundTrip() throws {
        let trip = makeTrip()
        let restored = try TripRecord(trip).trip()
        #expect(restored == trip)
    }

    @Test func placeRecordRoundTrip() {
        let place = Place(
            name: "School",
            coordinate: Coordinate(latitude: 41.88, longitude: -87.62),
            radiusM: 120,
            kind: .school,
            createdAt: t0
        )
        #expect(PlaceRecord(place).place() == place)
    }

    @Test func variantRecordRoundTrip() throws {
        let variant = RouteVariant(
            originPlaceID: UUID(),
            destinationPlaceID: UUID(),
            representativePolyline: Polyline(coordinates: [
                Coordinate(latitude: 41.9, longitude: -87.6),
                Coordinate(latitude: 41.95, longitude: -87.65),
            ]),
            autoName: "Route A",
            tripCount: 4,
            intersections: IntersectionInventory(
                signalCount: 7,
                stopSignCount: 2,
                coverageConfidence: .medium,
                fetchedAt: t0
            )
        )
        #expect(try VariantRecord(variant).variant() == variant)

        var bare = variant
        bare.intersections = nil
        #expect(try VariantRecord(bare).variant() == bare)
    }

    @Test func variantRecordWithoutEndpointsIsCorrupt() {
        let record = VariantRecord()
        record.polylineEncoded = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 1),
        ]).encoded()
        #expect(throws: StoreMappingError.self) { try record.variant() }
    }

    @Test func snapshotRecordRoundTrip() throws {
        let snapshot = PlanSnapshot(
            requestedAt: t0,
            destinationPlaceID: UUID(),
            polyline: Polyline(coordinates: [
                Coordinate(latitude: 41.9, longitude: -87.6),
                Coordinate(latitude: 41.92, longitude: -87.63),
            ]),
            distanceM: 9_100,
            staticDuration: 840,
            trafficDuration: 960,
            alternates: [
                .init(
                    polyline: Polyline(coordinates: [
                        Coordinate(latitude: 41.9, longitude: -87.6),
                        Coordinate(latitude: 41.93, longitude: -87.61),
                    ]),
                    staticDuration: 900,
                    trafficDuration: 990
                ),
            ]
        )
        #expect(try SnapshotRecord(snapshot).snapshot() == snapshot)
    }

    @Test func corruptTripBlobThrowsInsteadOfCrashing() throws {
        let record = try TripRecord(makeTrip())
        record.pointsBlob = Data("not json".utf8)
        #expect(throws: StoreMappingError.self) { try record.trip() }
    }

    @Test func recordsPersistAndFetchThroughAContainer() throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        let trip = makeTrip()
        context.insert(try TripRecord(trip))
        context.insert(PlaceRecord(Place(name: "Home", coordinate: Coordinate(latitude: 0, longitude: 0))))
        try context.save()

        let trips = try context.fetch(FetchDescriptor<TripRecord>())
        #expect(trips.count == 1)
        #expect(try trips[0].trip() == trip)
        let places = try context.fetch(FetchDescriptor<PlaceRecord>())
        #expect(places.count == 1)
        #expect(places[0].name == "Home")
    }
}
