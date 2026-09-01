import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import XCTest
@testable import RouteWarrior

/// FR-5/FR-6 wiring: at trip start the pipeline predicts the destination
/// and snapshots Google's plan through RoutesProviding; at finalize the
/// matching snapshot is attached, persisted, and the followed-plan label
/// computed. The stub proves the seam without a network.
@MainActor
final class SnapshotWiringTests: XCTestCase {
    private let metersPerDegree = 111_195.08

    private final class StubRoutes: RoutesProviding {
        let plan: Polyline

        init(plan: Polyline) {
            self.plan = plan
        }

        func computeSnapshot(
            from origin: Coordinate,
            to destination: Coordinate,
            destinationPlaceID: UUID?
        ) async throws -> PlanSnapshot {
            PlanSnapshot(
                requestedAt: .now,
                destinationPlaceID: destinationPlaceID,
                polyline: plan,
                distanceM: plan.lengthMeters,
                staticDuration: 600,
                trafficDuration: 700
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

    func testSnapshotIsFetchedAttachedAndLabeled() async throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)

        let home = Place(name: "Home", coordinate: Coordinate(latitude: 0, longitude: 0))
        let school = Place(name: "School", coordinate: Coordinate(latitude: 0, longitude: 0.09))
        context.insert(PlaceRecord(home))
        context.insert(PlaceRecord(school))

        // History so the predictor is confident: three earlier school runs
        // from home at the same weekday/slot as the test drive.
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        for week in 0..<3 {
            let start = t0.addingTimeInterval(Double(week) * 7 * 86_400)
            let history = Trip(
                startedAt: start,
                endedAt: start.addingTimeInterval(700),
                timezoneID: "America/Chicago",
                points: [
                    point(east: 0, at: start, speed: 12),
                    point(east: 600, at: start.addingTimeInterval(50), speed: 12),
                ],
                originPlaceID: home.id,
                destinationPlaceID: school.id
            )
            context.insert(try TripRecord(history))
        }
        try context.save()

        // Google's plan: the straight equator route the drive will follow.
        let plan = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 0.09),
        ])
        let pipeline = RecordingPipeline(
            context: context,
            timezoneID: "America/Chicago",
            routesProvider: StubRoutes(plan: plan)
        )

        // Same weekday/slot as history: three weeks after t0.
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
        // Let the (stubbed) snapshot fetch land before the trip ends.
        await pipeline.snapshotFetch?.value
        for _ in 0..<200 {
            pipeline.ingest(location: point(east: east, at: time, speed: 0))
            time = time.addingTimeInterval(1)
        }

        let trips = try context.fetch(FetchDescriptor<TripRecord>())
            .filter { $0.startedAt >= departure }
        XCTAssertEqual(trips.count, 1)
        let trip = try trips[0].trip()
        XCTAssertNotNil(trip.snapshotID)
        XCTAssertEqual(trip.followedPlan, true)

        let snapshots = try context.fetch(FetchDescriptor<SnapshotRecord>())
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].id, trip.snapshotID)
        XCTAssertEqual(snapshots[0].destinationPlaceID, school.id)
    }

    func testKeylessPipelineRecordsWithoutComparison() throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        let pipeline = RecordingPipeline(context: context, timezoneID: "America/Chicago")

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        pipeline.startManualRecording()
        var time = t0
        for i in 0..<200 {
            pipeline.ingest(location: point(east: Double(i) * 10, at: time, speed: 10))
            time = time.addingTimeInterval(1)
        }
        pipeline.stopManualRecording()

        let trips = try context.fetch(FetchDescriptor<TripRecord>())
        XCTAssertEqual(trips.count, 1)
        XCTAssertNil(trips[0].snapshotID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SnapshotRecord>()).count, 0)
    }
}
