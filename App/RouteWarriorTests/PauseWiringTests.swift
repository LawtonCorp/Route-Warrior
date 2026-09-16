import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import XCTest
@testable import RouteWarrior

/// D-069, across the kit/app boundary. The recorder's pause rules have
/// their own kit tests with a controlled clock; these assert the app
/// actually calls them — that the pipeline exposes the paused state the
/// buttons and the map badge key off, that samples arriving while paused
/// are dropped rather than recorded, and that a paused drive is still a
/// drive that ends up in the store.
@MainActor
final class PauseWiringTests: XCTestCase {
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

    /// Feeds `count` one-second samples 10 m apart, starting `from` metres
    /// east at `start`, and returns where it left off.
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

    private func makePipeline() throws -> (RecordingPipeline, ModelContext) {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        return (RecordingPipeline(context: context, timezoneID: "America/Chicago"), context)
    }

    func testPausingKeepsTheDriveOpenAndDropsWhatArrivesWhilePaused() throws {
        let (pipeline, context) = try makePipeline()
        pipeline.startManualRecording()
        let after = drive(pipeline, count: 200, from: 0, start: t0)

        pipeline.pauseRecording()
        XCTAssertTrue(pipeline.isPaused)
        XCTAssertFalse(pipeline.isRecording)
        // The controls and the live trail key off this: pausing must not
        // make the Stop button and the driven line disappear.
        XCTAssertTrue(pipeline.isDriveInProgress)
        XCTAssertNotNil(pipeline.recordingStartedAt)

        let kept = pipeline.liveTrack.count
        XCTAssertEqual(kept, 200)
        drive(pipeline, count: 100, from: after.east, start: after.time)
        XCTAssertEqual(pipeline.liveTrack.count, kept, "samples arriving while paused are not the drive")
        // Still open: a pause is not an ending, so nothing is stored yet.
        XCTAssertEqual(try context.fetch(FetchDescriptor<TripRecord>()).count, 0)

        pipeline.resumeRecording()
        XCTAssertTrue(pipeline.isRecording)
        XCTAssertFalse(pipeline.isPaused)

        drive(pipeline, count: 200, from: after.east + 1_000, start: after.time.addingTimeInterval(100))
        pipeline.stopManualRecording()

        // One trip, holding both driven stretches and neither of the
        // hundred samples that arrived while the clock was stopped.
        let trips = try context.fetch(FetchDescriptor<TripRecord>())
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(try trips[0].trip().points.count, 400)
    }

    func testStoppingWhilePausedStillSavesTheDrive() throws {
        let (pipeline, context) = try makePipeline()
        pipeline.startManualRecording()
        drive(pipeline, count: 200, from: 0, start: t0)

        pipeline.pauseRecording()
        pipeline.stopManualRecording()

        XCTAssertEqual(try context.fetch(FetchDescriptor<TripRecord>()).count, 1)
        XCTAssertFalse(pipeline.isDriveInProgress)
        XCTAssertEqual(pipeline.recorderState, .idle)
    }

    func testPauseAndResumeAreWrittenToTheRecorderLog() throws {
        let (pipeline, _) = try makePipeline()
        pipeline.startManualRecording()
        drive(pipeline, count: 200, from: 0, start: t0)

        pipeline.pauseRecording()
        XCTAssertTrue(pipeline.log.contains { $0.text.contains("Recording paused") })
        XCTAssertEqual(pipeline.lastOutcome, "Paused")

        pipeline.resumeRecording()
        XCTAssertTrue(pipeline.log.contains { $0.text.contains("Recording resumed") })
        XCTAssertEqual(pipeline.lastOutcome, "Recording")
    }

    /// Go on a paused drive continues it. Starting again would throw away
    /// the track already driven.
    func testGoOnAPausedDriveResumesItRatherThanStartingOver() throws {
        let (pipeline, _) = try makePipeline()
        pipeline.startManualRecording()
        drive(pipeline, count: 200, from: 0, start: t0)
        pipeline.pauseRecording()

        pipeline.startPlannedDrive(with: [])
        XCTAssertTrue(pipeline.isRecording)
        XCTAssertEqual(pipeline.liveTrack.count, 200, "the driven track survives Go on a paused drive")
    }

    func testPausingWhenNothingIsRecordingChangesNothing() throws {
        let (pipeline, _) = try makePipeline()
        pipeline.pauseRecording()
        XCTAssertEqual(pipeline.recorderState, .idle)
        XCTAssertFalse(pipeline.isPaused)
        pipeline.resumeRecording()
        XCTAssertEqual(pipeline.recorderState, .idle)
    }
}
