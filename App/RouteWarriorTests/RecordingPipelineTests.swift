import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import XCTest
@testable import RouteWarrior

/// The wiring test CLAUDE.md demands: a green kit suite says nothing about
/// whether the app actually calls it. This drives synthetic samples through
/// RecordingPipeline and asserts real records land in the store with places
/// and variants assigned.
@MainActor
final class RecordingPipelineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let metersPerDegree = 111_195.08

    private func point(east: Double, at time: Date, speed: Double) -> TrackPoint {
        TrackPoint(
            coordinate: Coordinate(latitude: 0, longitude: east / metersPerDegree),
            timestamp: time,
            speedMps: speed,
            courseDegrees: 90,
            horizontalAccuracyM: 5
        )
    }

    func testAutoDriveIsPersistedWithPlacesAndVariant() throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        context.insert(PlaceRecord(Place(name: "Home", coordinate: Coordinate(latitude: 0, longitude: 0))))
        context.insert(PlaceRecord(Place(name: "School", coordinate: Coordinate(latitude: 0, longitude: 0.09))))
        try context.save()

        let pipeline = RecordingPipeline(context: context, timezoneID: "America/Chicago")
        pipeline.ingest(motion: .init(kind: .automotive, confidence: .high, timestamp: t0))

        // Drive due east at 15 m/s to the school, then park.
        var east = 0.0
        var time = t0
        let target = 0.09 * metersPerDegree
        while east < target {
            pipeline.ingest(location: point(east: east, at: time, speed: 15))
            east += 15
            time = time.addingTimeInterval(1)
        }
        for _ in 0..<200 {
            pipeline.ingest(location: point(east: east, at: time, speed: 0))
            time = time.addingTimeInterval(1)
        }

        XCTAssertEqual(pipeline.recorderState, .idle)
        let trips = try context.fetch(FetchDescriptor<TripRecord>())
        XCTAssertEqual(trips.count, 1)
        let trip = try trips[0].trip()
        XCTAssertNotNil(trip.originPlaceID)
        XCTAssertNotNil(trip.destinationPlaceID)
        XCTAssertNotNil(trip.variantID)
        XCTAssertEqual(trip.source, .auto)
        XCTAssertGreaterThan(trip.distanceM, 9_500)

        let variants = try context.fetch(FetchDescriptor<VariantRecord>())
        XCTAssertEqual(variants.count, 1)
        XCTAssertEqual(variants[0].id, trip.variantID)
    }

    func testManualRecordingPersistsWithoutPlaces() throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        let pipeline = RecordingPipeline(context: context, timezoneID: "America/Chicago")

        pipeline.startManualRecording()
        XCTAssertTrue(pipeline.isRecording)
        var time = t0
        for i in 0..<200 {
            pipeline.ingest(location: point(east: Double(i) * 10, at: time, speed: 10))
            time = time.addingTimeInterval(1)
        }
        pipeline.stopManualRecording()

        let trips = try context.fetch(FetchDescriptor<TripRecord>())
        XCTAssertEqual(trips.count, 1)
        let trip = try trips[0].trip()
        XCTAssertEqual(trip.source, .manual)
        XCTAssertNil(trip.destinationPlaceID)
        XCTAssertNil(trip.variantID)
    }

    func testDiscardedJauntStoresNothing() throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        let pipeline = RecordingPipeline(context: context, timezoneID: "America/Chicago")

        pipeline.startManualRecording()
        pipeline.ingest(location: point(east: 0, at: t0, speed: 5))
        pipeline.ingest(location: point(east: 5, at: t0.addingTimeInterval(1), speed: 5))
        pipeline.stopManualRecording()

        XCTAssertEqual(try context.fetch(FetchDescriptor<TripRecord>()).count, 0)
        XCTAssertNotNil(pipeline.lastOutcome)
    }
}
