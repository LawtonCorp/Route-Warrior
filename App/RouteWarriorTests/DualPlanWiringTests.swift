import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import XCTest

@testable import RouteWarrior

/// D-022 "beat both" wiring: at departure every provider's plan is
/// fetched; at finalize the preferred provider's plan is the primary
/// snapshot (the one the driver saw), the other rides as the alternate,
/// and each gets its own followed label. Also the FR-20 path: a planned
/// drive to a searched address attaches its plan by proximity.
@MainActor
final class DualPlanWiringTests: XCTestCase {
    private let metersPerDegree = 111_195.08
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private struct Stub: RoutesProviding {
        let provider: PlanSnapshot.Provider
        let plan: Polyline
        let eta: TimeInterval

        func computeSnapshot(
            from origin: Coordinate,
            to destination: Coordinate,
            destinationPlaceID: UUID?
        ) async throws -> PlanSnapshot {
            PlanSnapshot(
                provider: provider,
                requestedAt: .now,
                destinationPlaceID: destinationPlaceID,
                polyline: plan,
                distanceM: plan.lengthMeters,
                staticDuration: eta,
                trafficDuration: eta
            )
        }
    }

    private func point(east: Double, at time: Date, speed: Double) -> TrackPoint {
        TrackPoint(
            coordinate: Coordinate(latitude: 0, longitude: east / metersPerDegree),
            timestamp: time,
            speedMps: speed,
            courseDegrees: 90,
            horizontalAccuracyM: 5
        )
    }

    private let straight = Polyline(coordinates: [
        Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 0.09),
    ])
    private let detour = Polyline(coordinates: [
        Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0.02, longitude: 0.045),
        Coordinate(latitude: 0, longitude: 0.09),
    ])

    /// Home → School with confident history, both providers stubbed.
    private func driveHomeToSchool(preferring preference: MapProvider) async throws -> (Trip, [SnapshotRecord]) {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        let home = Place(name: "Home", coordinate: Coordinate(latitude: 0, longitude: 0))
        let school = Place(name: "School", coordinate: Coordinate(latitude: 0, longitude: 0.09))
        context.insert(PlaceRecord(home))
        context.insert(PlaceRecord(school))
        for week in 0..<3 {
            let start = t0.addingTimeInterval(Double(week) * 7 * 86_400)
            context.insert(try TripRecord(Trip(
                startedAt: start,
                endedAt: start.addingTimeInterval(700),
                timezoneID: "America/Chicago",
                points: [point(east: 0, at: start, speed: 12), point(east: 600, at: start.addingTimeInterval(50), speed: 12)],
                originPlaceID: home.id,
                destinationPlaceID: school.id
            )))
        }
        try context.save()

        let pipeline = RecordingPipeline(
            context: context,
            timezoneID: "America/Chicago",
            providers: [
                .appleMaps: Stub(provider: .appleMaps, plan: straight, eta: 700),
                .googleRoutes: Stub(provider: .googleRoutes, plan: detour, eta: 650),
            ],
            preference: { preference }
        )
        let departure = t0.addingTimeInterval(3 * 7 * 86_400)
        pipeline.ingest(motion: .init(kind: .automotive, confidence: .high, timestamp: departure))
        var east = 0.0
        var time = departure
        let target = 0.09 * metersPerDegree
        while east < target {
            pipeline.ingest(location: point(east: east, at: time, speed: 15))
            east += 15
            time = time.addingTimeInterval(1)
        }
        await pipeline.snapshotFetch?.value
        for _ in 0..<200 {
            pipeline.ingest(location: point(east: east, at: time, speed: 0))
            time = time.addingTimeInterval(1)
        }
        let trips = try context.fetch(FetchDescriptor<TripRecord>()).filter { $0.startedAt >= departure }
        XCTAssertEqual(trips.count, 1)
        return (try trips[0].trip(), try context.fetch(FetchDescriptor<SnapshotRecord>()))
    }

    func testBothPlansAttachWithThePreferredAsPrimary() async throws {
        let (trip, snapshots) = try await driveHomeToSchool(preferring: .apple)
        XCTAssertEqual(snapshots.count, 2)
        let primary = try XCTUnwrap(snapshots.first { $0.id == trip.snapshotID })
        let alt = try XCTUnwrap(snapshots.first { $0.id == trip.altSnapshotID })
        XCTAssertEqual(primary.providerRaw, PlanSnapshot.Provider.appleMaps.rawValue)
        XCTAssertEqual(alt.providerRaw, PlanSnapshot.Provider.googleRoutes.rawValue)
        // The drive was the straight line: it followed Apple, not Google's detour.
        XCTAssertEqual(trip.followedPlan, true)
        XCTAssertEqual(trip.followedAltPlan, false)
    }

    func testThePreferenceDecidesWhichPlanIsPrimary() async throws {
        let (trip, snapshots) = try await driveHomeToSchool(preferring: .google)
        let primary = try XCTUnwrap(snapshots.first { $0.id == trip.snapshotID })
        XCTAssertEqual(primary.providerRaw, PlanSnapshot.Provider.googleRoutes.rawValue)
        XCTAssertEqual(trip.followedPlan, false)
        XCTAssertEqual(trip.followedAltPlan, true)
    }

    func testAPlannedDriveToASearchedAddressAttachesByProximity() throws {
        // No saved places at all: the plan ends where the drive ends.
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        let pipeline = RecordingPipeline(context: context, timezoneID: "America/Chicago")
        let plan = PlanSnapshot(
            provider: .appleMaps, requestedAt: t0, polyline: straight,
            distanceM: straight.lengthMeters, staticDuration: 700, trafficDuration: 700
        )
        pipeline.startPlannedDrive(with: [plan])
        XCTAssertTrue(pipeline.isRecording)
        var east = 0.0
        var time = t0
        let target = 0.09 * metersPerDegree
        while east < target {
            pipeline.ingest(location: point(east: east, at: time, speed: 15))
            east += 15
            time = time.addingTimeInterval(1)
        }
        pipeline.stopManualRecording()

        let trips = try context.fetch(FetchDescriptor<TripRecord>())
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].snapshotID, plan.id)
        XCTAssertNil(trips[0].altSnapshotID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SnapshotRecord>()).count, 1)
        XCTAssertEqual(try trips[0].trip().followedPlan, true)
    }

    func testArrivalMatchingIsByPlaceOrByProximity() {
        let school = Place(name: "School", coordinate: Coordinate(latitude: 0, longitude: 0.09))
        let forSchool = PlanSnapshot(
            provider: .appleMaps, requestedAt: t0, destinationPlaceID: school.id, polyline: straight,
            distanceM: 0, staticDuration: 0, trafficDuration: 0
        )
        let unnamed = PlanSnapshot(
            provider: .appleMaps, requestedAt: t0, polyline: straight,
            distanceM: 0, staticDuration: 0, trafficDuration: 0
        )
        let atSchool = Coordinate(latitude: 0, longitude: 0.09)
        let nearby = Coordinate(latitude: 0, longitude: 0.0913) // ~145 m
        let farOff = Coordinate(latitude: 0, longitude: 0.093) // ~333 m
        XCTAssertTrue(RecordingPipeline.snapshot(forSchool, matchesArrivalAt: farOff, place: school))
        XCTAssertTrue(RecordingPipeline.snapshot(unnamed, matchesArrivalAt: nearby, place: nil))
        XCTAssertFalse(RecordingPipeline.snapshot(unnamed, matchesArrivalAt: farOff, place: nil))
        XCTAssertFalse(RecordingPipeline.snapshot(unnamed, matchesArrivalAt: nil, place: nil))
        XCTAssertTrue(RecordingPipeline.snapshot(unnamed, matchesArrivalAt: atSchool, place: school))
    }
}
