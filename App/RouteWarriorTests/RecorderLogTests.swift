import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import XCTest

@testable import RouteWarrior

/// D-019 wiring: the recorder log and the discard detail are what a field
/// test reads off the phone, so the pipeline must actually write them.
@MainActor
final class RecorderLogTests: XCTestCase {
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

    private func makePipeline() throws -> RecordingPipeline {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        return RecordingPipeline(context: ModelContext(container), timezoneID: "America/Chicago")
    }

    func testDiscardSaysWhatEndedTheSegmentAndWhatItHeld() throws {
        let pipeline = try makePipeline()
        pipeline.ingest(motion: .init(kind: .automotive, confidence: .high, timestamp: t0))
        XCTAssertTrue(pipeline.log.contains { $0.text.hasPrefix("Armed") })

        var time = t0
        for i in 0..<40 {
            pipeline.ingest(location: point(east: Double(i) * 15, at: time, speed: 15))
            time = time.addingTimeInterval(1)
        }
        for _ in 0..<200 {
            pipeline.ingest(location: point(east: 40 * 15, at: time, speed: 0))
            time = time.addingTimeInterval(1)
        }

        XCTAssertEqual(pipeline.recorderState, .idle)
        let outcome = try XCTUnwrap(pipeline.lastOutcome)
        XCTAssertTrue(outcome.hasPrefix("Trip too brief to keep"), outcome)
        XCTAssertTrue(outcome.contains("3 min idle"), outcome)
        XCTAssertTrue(outcome.contains("40 points"), outcome)
        XCTAssertTrue(pipeline.log.contains { $0.text.hasPrefix("First location sample") })
        XCTAssertTrue(pipeline.log.contains { $0.text.hasPrefix("Recording started") })
        XCTAssertEqual(pipeline.log.last?.text, outcome)
    }

    func testStationaryAtALightDoesNotEndARecordingThroughThePipeline() throws {
        let pipeline = try makePipeline()
        pipeline.ingest(motion: .init(kind: .automotive, confidence: .high, timestamp: t0))
        var time = t0
        for i in 0..<60 {
            pipeline.ingest(location: point(east: Double(i) * 15, at: time, speed: 15))
            time = time.addingTimeInterval(1)
        }
        XCTAssertTrue(pipeline.isRecording)
        pipeline.ingest(motion: .init(kind: .stationary, confidence: .high, timestamp: time))
        XCTAssertTrue(pipeline.isRecording, "a red light must not end the drive")
    }

    func testLogIsCappedNewestLast() throws {
        let pipeline = try makePipeline()
        for i in 0..<(RecordingPipeline.logCapacity + 20) {
            pipeline.note("event \(i)")
        }
        XCTAssertEqual(pipeline.log.count, RecordingPipeline.logCapacity)
        XCTAssertEqual(pipeline.log.last?.text, "event \(RecordingPipeline.logCapacity + 19)")
        pipeline.clearLog()
        XCTAssertTrue(pipeline.log.isEmpty)
    }

    func testLogSurvivesARelaunchThroughItsStorage() throws {
        let suiteName = "RecorderLogTests-\(UUID().uuidString)"
        let storage = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { storage.removePersistentDomain(forName: suiteName) }
        let container = try RouteWarriorStoreFactory.inMemoryContainer()

        let first = RecordingPipeline(context: ModelContext(container), logStorage: storage)
        first.note("before the app was killed")

        let second = RecordingPipeline(context: ModelContext(container), logStorage: storage)
        XCTAssertEqual(second.log.map(\.text), ["before the app was killed"])
    }
}
