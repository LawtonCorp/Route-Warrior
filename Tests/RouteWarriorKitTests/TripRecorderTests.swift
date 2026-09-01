import Foundation
import Testing
@testable import RouteWarriorKit

/// Synthetic drives along the equator, built at 1 Hz by `DriveBuilder`.
/// Inputs are synthetic; expectations are hand geometry (points spaced
/// `speed` meters apart, so a 300 s cruise at 15 m/s covers 299 × 15 m) —
/// the recorder never grades its own output.
struct TripRecorderTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let tz = "America/Chicago"

    private struct DriveBuilder {
        var points: [TrackPoint] = []
        var time: Date
        var eastMeters: Double = 0
        private let metersPerDegree = 111_195.08

        init(start: Date) { self.time = start }

        mutating func drive(speedMps: Double, seconds: Int, accuracyM: Double = 5) {
            for _ in 0..<seconds {
                points.append(TrackPoint(
                    coordinate: Coordinate(latitude: 0, longitude: eastMeters / metersPerDegree),
                    timestamp: time,
                    speedMps: speedMps,
                    courseDegrees: 90,
                    horizontalAccuracyM: accuracyM
                ))
                eastMeters += speedMps
                time = time.addingTimeInterval(1)
            }
        }
    }

    private func automotive(_ at: Date) -> TripRecorder.MotionSample {
        .init(kind: .automotive, confidence: .high, timestamp: at)
    }

    /// Feeds every point, returning the outputs in order.
    private func feed(_ points: [TrackPoint], into recorder: inout TripRecorder) -> [TripRecorder.Output] {
        points.compactMap { recorder.ingest(location: $0) }
    }

    private func finalizedTrip(in outputs: [TripRecorder.Output]) -> Trip? {
        for case .tripFinalized(let trip) in outputs { return trip }
        return nil
    }

    // MARK: Auto lifecycle

    @Test func happyPathDriveIsRecordedAndTrailingIdleTrimmed() {
        var recorder = TripRecorder(timezoneID: tz)
        #expect(recorder.ingest(motion: automotive(t0)) == nil)
        #expect(recorder.state == .armed)

        var builder = DriveBuilder(start: t0)
        builder.drive(speedMps: 15, seconds: 300)
        builder.drive(speedMps: 0, seconds: 200)
        let outputs = feed(builder.points, into: &recorder)

        #expect(outputs.contains(.tripStarted(t0)))
        let trip = finalizedTrip(in: outputs)
        #expect(trip != nil)
        #expect(recorder.state == .idle)
        guard let trip else { return }
        #expect(trip.startedAt == t0)
        // Trailing idle is trimmed: the trip ends at the last moving point.
        #expect(trip.endedAt == t0.addingTimeInterval(299))
        #expect(abs(trip.distanceM - 299 * 15) < 299 * 15 * 0.01)
        #expect(trip.source == .auto)
        #expect(trip.timezoneID == tz)
        #expect(abs(trip.movingTime - 299) < 2)
        #expect(trip.idleTime < 2)
    }

    @Test func slowLongDriveBelowMinimumDistanceIsDiscardedTooShort() {
        var recorder = TripRecorder(timezoneID: tz)
        _ = recorder.ingest(motion: automotive(t0))
        var builder = DriveBuilder(start: t0)
        builder.drive(speedMps: 4, seconds: 190) // 756 m — under the 800 m floor
        builder.drive(speedMps: 0, seconds: 200)
        let outputs = feed(builder.points, into: &recorder)
        #expect(outputs.contains(.tripDiscarded(.tooShort)))
        #expect(finalizedTrip(in: outputs) == nil)
    }

    @Test func briefJauntIsDiscardedTooBrief() {
        var recorder = TripRecorder(timezoneID: tz)
        _ = recorder.ingest(motion: automotive(t0))
        var builder = DriveBuilder(start: t0)
        builder.drive(speedMps: 15, seconds: 40)
        builder.drive(speedMps: 0, seconds: 200)
        let outputs = feed(builder.points, into: &recorder)
        #expect(outputs.contains(.tripDiscarded(.tooBrief)))
    }

    @Test func garageColdStartTriggersOnDisplacement() {
        // Never reaches the 4.5 m/s start speed, but creeps 500 m from the
        // arming spot — the displacement trigger must catch it and keep the
        // full pre-trigger buffer.
        var recorder = TripRecorder(timezoneID: tz)
        _ = recorder.ingest(motion: automotive(t0))
        var builder = DriveBuilder(start: t0)
        builder.drive(speedMps: 3, seconds: 200) // 600 m of creep
        builder.drive(speedMps: 15, seconds: 200)
        builder.drive(speedMps: 0, seconds: 200)
        let outputs = feed(builder.points, into: &recorder)
        let trip = finalizedTrip(in: outputs)
        #expect(trip != nil)
        guard let trip else { return }
        #expect(trip.startedAt == t0)
        let expected = 3.0 * 200 + 15.0 * 199
        #expect(abs(trip.distanceM - expected) < expected * 0.01)
    }

    @Test func driveThroughIdleShorterThanWindowStaysOneTrip() {
        var recorder = TripRecorder(timezoneID: tz)
        _ = recorder.ingest(motion: automotive(t0))
        var builder = DriveBuilder(start: t0)
        builder.drive(speedMps: 15, seconds: 120)
        builder.drive(speedMps: 0, seconds: 150) // under the 180 s idle window
        builder.drive(speedMps: 15, seconds: 120)
        builder.drive(speedMps: 0, seconds: 200)
        let outputs = feed(builder.points, into: &recorder)
        let finalized = outputs.filter { if case .tripFinalized = $0 { true } else { false } }
        #expect(finalized.count == 1)
        guard let trip = finalizedTrip(in: outputs) else { return }
        #expect(abs(trip.idleTime - 150) < 5)
        #expect(trip.endedAt == t0.addingTimeInterval(389))
    }

    @Test func redLightAtEndPlusWalkingFinalizesTrimmed() {
        var recorder = TripRecorder(timezoneID: tz)
        _ = recorder.ingest(motion: automotive(t0))
        var builder = DriveBuilder(start: t0)
        builder.drive(speedMps: 15, seconds: 300)
        builder.drive(speedMps: 0, seconds: 60) // parked, but idle window not yet over
        var outputs = feed(builder.points, into: &recorder)
        let walking = TripRecorder.MotionSample(
            kind: .walking, confidence: .high, timestamp: builder.time
        )
        if let output = recorder.ingest(motion: walking) { outputs.append(output) }
        guard let trip = finalizedTrip(in: outputs) else {
            Issue.record("walking away from a parked car must finalize the trip")
            return
        }
        #expect(trip.endedAt == t0.addingTimeInterval(299))
    }

    @Test func gapInStreamSplitsTheTrip() {
        var recorder = TripRecorder(timezoneID: tz)
        _ = recorder.ingest(motion: automotive(t0))
        var builder = DriveBuilder(start: t0)
        builder.drive(speedMps: 15, seconds: 300)
        var outputs = feed(builder.points, into: &recorder)
        let afterGap = TrackPoint(
            coordinate: Coordinate(latitude: 0, longitude: 1),
            timestamp: t0.addingTimeInterval(299 + 400),
            speedMps: 15,
            horizontalAccuracyM: 5
        )
        if let output = recorder.ingest(location: afterGap) { outputs.append(output) }
        let trip = finalizedTrip(in: outputs)
        #expect(trip != nil)
        #expect(trip?.endedAt == t0.addingTimeInterval(299))
        #expect(recorder.state == .idle)
    }

    // MARK: Arming

    @Test func lowConfidenceMotionNeverArms() {
        var recorder = TripRecorder(timezoneID: tz)
        _ = recorder.ingest(motion: .init(kind: .automotive, confidence: .low, timestamp: t0))
        #expect(recorder.state == .idle)
    }

    @Test func walkingBeforeMovementDisarms() {
        var recorder = TripRecorder(timezoneID: tz)
        _ = recorder.ingest(motion: automotive(t0))
        #expect(recorder.state == .armed)
        _ = recorder.ingest(motion: .init(kind: .walking, confidence: .high, timestamp: t0.addingTimeInterval(20)))
        #expect(recorder.state == .idle)
    }

    @Test func inaccuratePointsAreIgnored() {
        var recorder = TripRecorder(timezoneID: tz)
        _ = recorder.ingest(motion: automotive(t0))
        var noisy = DriveBuilder(start: t0)
        noisy.drive(speedMps: 15, seconds: 60, accuracyM: 120)
        let outputs = feed(noisy.points, into: &recorder)
        // A minute of driving-speed points, all too inaccurate to trust:
        // nothing may start.
        #expect(outputs.isEmpty)
        #expect(recorder.state == .armed)

        var invalid = DriveBuilder(start: t0.addingTimeInterval(60))
        invalid.drive(speedMps: 15, seconds: 60, accuracyM: -1)
        #expect(feed(invalid.points, into: &recorder).isEmpty)
        #expect(recorder.state == .armed)
    }

    // MARK: Manual controls

    @Test func manualRecordingRoundTrip() {
        var recorder = TripRecorder(timezoneID: tz)
        recorder.startManualRecording(at: t0)
        #expect(recorder.state == .recording)
        var builder = DriveBuilder(start: t0)
        builder.drive(speedMps: 10, seconds: 200)
        var outputs = feed(builder.points, into: &recorder)
        if let output = recorder.stopRecording() { outputs.append(output) }
        guard let trip = finalizedTrip(in: outputs) else {
            Issue.record("manual stop after a real drive must finalize")
            return
        }
        #expect(trip.source == .manual)
        #expect(abs(trip.distanceM - 199 * 10) < 199 * 10 * 0.01)
    }

    @Test func manualStopWithNothingRecordedDiscards() {
        var recorder = TripRecorder(timezoneID: tz)
        recorder.startManualRecording(at: t0)
        let output = recorder.stopRecording()
        #expect(output == .tripDiscarded(.tooBrief))
        #expect(recorder.stopRecording() == nil) // already idle
    }
}
