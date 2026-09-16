import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import XCTest
@testable import RouteWarrior

/// D-072 across the kit/app boundary. `PauseWatch` has its own kit tests
/// for the arithmetic; these assert the app reads the clock, asks once,
/// stops the drive on time, and that "Still here" actually buys more
/// time rather than only dismissing a box.
@MainActor
final class PauseTimeoutWiringTests: XCTestCase {
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

    private func drive(_ pipeline: RecordingPipeline, count: Int, from east: Double, start: Date) {
        var east = east
        var time = start
        for _ in 0..<count {
            pipeline.ingest(location: point(east: east, at: time, speed: 10))
            east += 10
            time = time.addingTimeInterval(1)
        }
    }

    /// A recording drive, paused at `t0 + 200`, with the default limit.
    private func pausedDrive(
        limitMinutes: Int = 20
    ) throws -> (RecordingPipeline, ModelContext, paused: Date) {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        let pipeline = RecordingPipeline(
            context: context,
            timezoneID: "America/Chicago",
            pauseWatch: { PauseWatch.Config(limit: Double(limitMinutes) * 60) }
        )
        pipeline.startManualRecording()
        drive(pipeline, count: 200, from: 0, start: t0)
        let paused = t0.addingTimeInterval(200)
        pipeline.pauseRecording(at: paused)
        XCTAssertTrue(pipeline.isPaused)
        return (pipeline, context, paused)
    }

    func testTheQuestionIsAskedOnceAtTwelveMinutes() throws {
        let (pipeline, _, paused) = try pausedDrive()
        var asked: [Int] = []
        pipeline.onPauseStillThere = { asked.append($0) }

        pipeline.checkPause(at: paused.addingTimeInterval(11 * 60))
        XCTAssertFalse(pipeline.pauseNeedsAnswer)
        XCTAssertTrue(asked.isEmpty)

        pipeline.checkPause(at: paused.addingTimeInterval(12 * 60))
        XCTAssertTrue(pipeline.pauseNeedsAnswer)
        XCTAssertEqual(asked, [20], "the limit goes with the question, for the wording")

        // Every later sample is another tick; the driver is asked once.
        pipeline.checkPause(at: paused.addingTimeInterval(13 * 60))
        pipeline.checkPause(at: paused.addingTimeInterval(14 * 60))
        XCTAssertEqual(asked, [20])
    }

    func testTheDriveStopsItselfAtTheLimitAndIsSaved() throws {
        let (pipeline, context, paused) = try pausedDrive()
        var withdrawn = 0
        pipeline.onPauseAnswered = { withdrawn += 1 }
        pipeline.checkPause(at: paused.addingTimeInterval(12 * 60))

        pipeline.checkPause(at: paused.addingTimeInterval(20 * 60))
        XCTAssertFalse(pipeline.isDriveInProgress)
        XCTAssertEqual(pipeline.recorderState, .idle)
        XCTAssertFalse(pipeline.pauseNeedsAnswer)
        XCTAssertEqual(withdrawn, 1, "the question is withdrawn wherever it was asked")

        // Saved, not discarded — and per D-069 it ends where it paused,
        // so the twenty minutes of sitting are not in the drive.
        let trips = try context.fetch(FetchDescriptor<TripRecord>())
        XCTAssertEqual(trips.count, 1)
        let trip = try trips[0].trip()
        XCTAssertEqual(trip.pausedTime, 0)
        XCTAssertEqual(trip.endedAt, t0.addingTimeInterval(199))
        XCTAssertTrue(pipeline.log.contains { $0.text.contains("stopped and saved") })
    }

    func testStillHereBuysAnotherFullLimit() throws {
        let (pipeline, context, paused) = try pausedDrive()
        pipeline.checkPause(at: paused.addingTimeInterval(12 * 60))
        XCTAssertTrue(pipeline.pauseNeedsAnswer)

        pipeline.keepPaused(at: paused.addingTimeInterval(12 * 60))
        XCTAssertFalse(pipeline.pauseNeedsAnswer)

        // What would have been the stop is now well inside the new lease.
        pipeline.checkPause(at: paused.addingTimeInterval(20 * 60))
        XCTAssertTrue(pipeline.isPaused)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TripRecord>()).count, 0)

        // Asked again a full twelve minutes after the answer, not sooner.
        pipeline.checkPause(at: paused.addingTimeInterval(23 * 60))
        XCTAssertFalse(pipeline.pauseNeedsAnswer)
        pipeline.checkPause(at: paused.addingTimeInterval(24 * 60))
        XCTAssertTrue(pipeline.pauseNeedsAnswer)

        // And the stop moved with it.
        pipeline.checkPause(at: paused.addingTimeInterval(32 * 60))
        XCTAssertEqual(try context.fetch(FetchDescriptor<TripRecord>()).count, 1)
    }

    /// Dismissing the box is not an answer: the drive still stops on time.
    func testDismissingTheQuestionDoesNotExtendThePause() throws {
        let (pipeline, context, paused) = try pausedDrive()
        pipeline.checkPause(at: paused.addingTimeInterval(12 * 60))
        pipeline.dismissPauseQuestion()
        XCTAssertFalse(pipeline.pauseNeedsAnswer)

        pipeline.checkPause(at: paused.addingTimeInterval(20 * 60))
        XCTAssertEqual(try context.fetch(FetchDescriptor<TripRecord>()).count, 1)
    }

    /// The driver's own setting drives both thresholds, not just the stop.
    func testAShorterLimitMovesTheQuestionWithIt() throws {
        let (pipeline, context, paused) = try pausedDrive(limitMinutes: 5)
        var asked: [Int] = []
        pipeline.onPauseStillThere = { asked.append($0) }

        pipeline.checkPause(at: paused.addingTimeInterval(2 * 60))
        XCTAssertFalse(pipeline.pauseNeedsAnswer)
        pipeline.checkPause(at: paused.addingTimeInterval(3 * 60))
        XCTAssertEqual(asked, [5], "60% of five minutes, so the question still comes first")

        pipeline.checkPause(at: paused.addingTimeInterval(5 * 60))
        XCTAssertEqual(try context.fetch(FetchDescriptor<TripRecord>()).count, 1)
    }

    /// Resuming ends the watch: the deadline must not survive to stop a
    /// drive that is running again.
    func testResumingClearsTheDeadline() throws {
        let (pipeline, context, paused) = try pausedDrive()
        pipeline.checkPause(at: paused.addingTimeInterval(12 * 60))
        var withdrawn = 0
        pipeline.onPauseAnswered = { withdrawn += 1 }

        pipeline.resumeRecording(at: paused.addingTimeInterval(13 * 60))
        XCTAssertTrue(pipeline.isRecording)
        XCTAssertFalse(pipeline.pauseNeedsAnswer)
        XCTAssertEqual(withdrawn, 1)

        pipeline.checkPause(at: paused.addingTimeInterval(60 * 60))
        XCTAssertTrue(pipeline.isRecording, "a running drive has no pause deadline")
        XCTAssertEqual(try context.fetch(FetchDescriptor<TripRecord>()).count, 0)
    }

    /// The samples that keep arriving while paused are what carry the
    /// deadline with the app off screen (D-069 keeps the GPS on).
    func testAnArrivingSampleCarriesTheDeadline() throws {
        let (pipeline, context, paused) = try pausedDrive()
        pipeline.ingest(location: point(east: 2_000, at: paused.addingTimeInterval(12 * 60), speed: 0))
        XCTAssertTrue(pipeline.pauseNeedsAnswer)

        pipeline.ingest(location: point(east: 2_000, at: paused.addingTimeInterval(20 * 60), speed: 0))
        XCTAssertEqual(try context.fetch(FetchDescriptor<TripRecord>()).count, 1)
    }

    func testARunningDriveIsNeverStoppedByTheWatch() throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        let pipeline = RecordingPipeline(context: context, timezoneID: "America/Chicago")
        pipeline.startManualRecording()
        drive(pipeline, count: 200, from: 0, start: t0)

        pipeline.checkPause(at: t0.addingTimeInterval(60 * 60))
        XCTAssertTrue(pipeline.isRecording)
        XCTAssertFalse(pipeline.pauseNeedsAnswer)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TripRecord>()).count, 0)
    }
}
