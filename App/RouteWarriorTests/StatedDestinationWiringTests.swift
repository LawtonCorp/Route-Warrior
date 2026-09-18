import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import XCTest
@testable import RouteWarrior

/// D-081, across the kit/app boundary. The matcher's rule has its own kit
/// tests; these assert the app actually carries the driver's answer to
/// it. Tapping a place on the departure notification used to buy a plan
/// and nothing else, so a drive the driver had named still finished with
/// no destination — and with no destination there is no route, no
/// comparison and nothing on the Destination screen.
@MainActor
final class StatedDestinationWiringTests: XCTestCase {
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

    @discardableResult
    private func drive(
        _ pipeline: RecordingPipeline, count: Int, from east: Double, start: Date
    ) -> (east: Double, time: Date) {
        var east = east
        var time = start
        for _ in 0..<count {
            pipeline.ingest(location: point(east: east, at: time, speed: 10))
            east += 10
            time = time.addingTimeInterval(1)
        }
        return (east, time)
    }

    /// A place `east` metres along the drive's line.
    private func place(_ name: String, east: Double, in context: ModelContext) -> PlaceRecord {
        let record = PlaceRecord(Place(
            name: name,
            coordinate: Coordinate(latitude: 0, longitude: east / metersPerDegree)
        ))
        context.insert(record)
        return record
    }

    private func makePipeline() throws -> (RecordingPipeline, ModelContext) {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        // No providers: the point is that the *name* survives even when
        // no plan can be fetched for it.
        return (RecordingPipeline(context: context, timezoneID: "America/Chicago"), context)
    }

    private func storedTrip(in context: ModelContext) throws -> TripRecord? {
        try context.fetch(FetchDescriptor<TripRecord>()).first
    }

    /// The drive runs 2 km east and stops 300 m short of the school —
    /// outside its 75 m fence and outside the 200 m tolerance, which is
    /// the case the driver's answer exists for.
    func testTheDriversPickNamesTheStoredTrip() throws {
        let (pipeline, context) = try makePipeline()
        let school = place("School", east: 2_300, in: context)
        try context.save()

        pipeline.startManualRecording()
        let after = drive(pipeline, count: 200, from: 0, start: t0)
        pipeline.requestSnapshot(to: school.id)
        pipeline.stopManualRecording(at: after.time)

        let trip = try XCTUnwrap(storedTrip(in: context))
        XCTAssertEqual(trip.destinationPlaceID, school.id)
    }

    /// The same drive with nobody answering: unchanged behaviour, no
    /// destination invented.
    func testWithoutAPickTheTripStillNamesNoDestination() throws {
        let (pipeline, context) = try makePipeline()
        _ = place("School", east: 2_300, in: context)
        try context.save()

        pipeline.startManualRecording()
        let after = drive(pipeline, count: 200, from: 0, start: t0)
        pipeline.stopManualRecording(at: after.time)

        let trip = try XCTUnwrap(storedTrip(in: context))
        XCTAssertNil(trip.destinationPlaceID)
    }

    /// The pick arrives while the drive is paused — the driver read the
    /// notification at the kerb. It must still count: the old code
    /// returned early unless the recorder was actively recording, and
    /// threw the answer away with the fetch it could not make.
    func testAPickWhilePausedStillNamesTheTrip() throws {
        let (pipeline, context) = try makePipeline()
        let school = place("School", east: 2_300, in: context)
        try context.save()

        pipeline.startManualRecording()
        let after = drive(pipeline, count: 200, from: 0, start: t0)
        pipeline.pauseRecording(at: after.time)
        pipeline.requestSnapshot(to: school.id)
        pipeline.stopManualRecording(at: after.time.addingTimeInterval(60))

        let trip = try XCTUnwrap(storedTrip(in: context))
        XCTAssertEqual(trip.destinationPlaceID, school.id)
    }

    /// Where the drive ended outranks what was said about it: the answer
    /// fills a gap, it does not overwrite the track.
    func testArrivingSomewhereElseKeepsTheTruth() throws {
        let (pipeline, context) = try makePipeline()
        let school = place("School", east: 2_300, in: context)
        let shop = place("The shop", east: 1_990, in: context)
        try context.save()

        pipeline.startManualRecording()
        let after = drive(pipeline, count: 200, from: 0, start: t0)
        pipeline.requestSnapshot(to: school.id)
        pipeline.stopManualRecording(at: after.time)

        let trip = try XCTUnwrap(storedTrip(in: context))
        XCTAssertEqual(trip.destinationPlaceID, shop.id,
                       "the drive ended at the shop, whatever the driver said earlier")
    }

    /// The answer belongs to the drive that was open when it was given.
    func testTheNameDoesNotLeakIntoTheNextDrive() throws {
        let (pipeline, context) = try makePipeline()
        let school = place("School", east: 2_300, in: context)
        try context.save()

        pipeline.startManualRecording()
        let first = drive(pipeline, count: 200, from: 0, start: t0)
        pipeline.requestSnapshot(to: school.id)
        pipeline.stopManualRecording(at: first.time)

        pipeline.startManualRecording()
        let second = drive(pipeline, count: 200, from: 10_000, start: first.time.addingTimeInterval(3_600))
        pipeline.stopManualRecording(at: second.time)

        let trips = try context.fetch(FetchDescriptor<TripRecord>())
            .sorted { $0.startedAt < $1.startedAt }
        XCTAssertEqual(trips.count, 2)
        XCTAssertEqual(trips.first?.destinationPlaceID, school.id)
        XCTAssertNil(trips.last?.destinationPlaceID, "a new drive starts unnamed")
    }
}
