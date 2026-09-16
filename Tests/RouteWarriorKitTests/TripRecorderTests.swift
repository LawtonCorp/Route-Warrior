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

    // MARK: Motion-end robustness (D-019)

    @Test func stationaryAtARedLightDoesNotEndTheTrip() {
        // CoreMotion reports "stationary" for a car waiting at a light. That
        // used to finalize on the spot, chopping a drive into sub-3-minute
        // fragments that were all discarded as too brief.
        var recorder = TripRecorder(timezoneID: tz)
        _ = recorder.ingest(motion: automotive(t0))
        var builder = DriveBuilder(start: t0)
        builder.drive(speedMps: 15, seconds: 120)
        builder.drive(speedMps: 0, seconds: 90) // a long light
        var outputs = feed(builder.points, into: &recorder)
        let stationary = TripRecorder.MotionSample(
            kind: .stationary, confidence: .high, timestamp: builder.time
        )
        #expect(recorder.ingest(motion: stationary) == nil)
        #expect(recorder.state == .recording)

        let fed = builder.points.count
        builder.drive(speedMps: 15, seconds: 120)
        builder.drive(speedMps: 0, seconds: 200)
        outputs += feed(Array(builder.points[fed...]), into: &recorder)

        let finalized = outputs.filter { if case .tripFinalized = $0 { true } else { false } }
        #expect(finalized.count == 1)
        guard let trip = finalizedTrip(in: outputs) else { return }
        #expect(trip.endedAt == t0.addingTimeInterval(329))
        #expect(abs(trip.distanceM - 3585) < 3585 * 0.01)
        #expect(abs(trip.idleTime - 90) < 5)
        #expect(recorder.lastEndCause == .idleTimeout)
    }

    @Test func spuriousWalkingWhileCruisingDoesNotEndTheTrip() {
        var recorder = TripRecorder(timezoneID: tz)
        _ = recorder.ingest(motion: automotive(t0))
        var builder = DriveBuilder(start: t0)
        builder.drive(speedMps: 15, seconds: 120)
        var outputs = feed(builder.points, into: &recorder)
        // One misclassified sample at highway speed.
        let walking = TripRecorder.MotionSample(
            kind: .walking, confidence: .high, timestamp: builder.time
        )
        #expect(recorder.ingest(motion: walking) == nil)
        #expect(recorder.state == .recording)

        let fed = builder.points.count
        builder.drive(speedMps: 15, seconds: 120) // still cruising: suspicion clears
        builder.drive(speedMps: 0, seconds: 200)
        outputs += feed(Array(builder.points[fed...]), into: &recorder)

        let finalized = outputs.filter { if case .tripFinalized = $0 { true } else { false } }
        #expect(finalized.count == 1)
        guard let trip = finalizedTrip(in: outputs) else { return }
        #expect(trip.endedAt == t0.addingTimeInterval(239))
        #expect(abs(trip.distanceM - 239 * 15) < 239 * 15 * 0.01)
    }

    @Test func walkingRightAfterStoppingIsConfirmedByLocationAndTrimmed() {
        // Parked and out of the car within the grace window: the walking
        // sample alone is a suspect; twenty seconds of walking-pace points
        // confirm it, and the walk itself is not part of the drive.
        var recorder = TripRecorder(timezoneID: tz)
        _ = recorder.ingest(motion: automotive(t0))
        var builder = DriveBuilder(start: t0)
        builder.drive(speedMps: 15, seconds: 300)
        builder.drive(speedMps: 0, seconds: 10)
        var outputs = feed(builder.points, into: &recorder)
        let walking = TripRecorder.MotionSample(
            kind: .walking, confidence: .medium, timestamp: builder.time
        )
        #expect(recorder.ingest(motion: walking) == nil)
        #expect(recorder.state == .recording)

        let fed = builder.points.count
        builder.drive(speedMps: 1.4, seconds: 30)
        outputs += feed(Array(builder.points[fed...]), into: &recorder)

        guard let trip = finalizedTrip(in: outputs) else {
            Issue.record("walking-pace points after a walking sample must finalize")
            return
        }
        #expect(recorder.state == .idle)
        #expect(recorder.lastEndCause == .pedestrianMotion)
        #expect(trip.endedAt == t0.addingTimeInterval(299))
        #expect(abs(trip.distanceM - 299 * 15) < 299 * 15 * 0.01)
    }

    @Test func endCauseAndSegmentSummaryDescribeADiscard() {
        var recorder = TripRecorder(timezoneID: tz)
        _ = recorder.ingest(motion: automotive(t0))
        var builder = DriveBuilder(start: t0)
        builder.drive(speedMps: 15, seconds: 40)
        builder.drive(speedMps: 0, seconds: 200)
        let outputs = feed(builder.points, into: &recorder)
        #expect(outputs.contains(.tripDiscarded(.tooBrief)))
        #expect(recorder.lastEndCause == .idleTimeout)
        // 40 driving points over 39 s covering 39 hops of 15 m.
        #expect(recorder.lastSegment?.points == 40)
        #expect(recorder.lastSegment?.duration == 39)
        #expect(abs((recorder.lastSegment?.distanceM ?? 0) - 585) < 6)
        #expect(recorder.lastSegment?.rejectedPoints == 0)
    }

    @Test func rejectedPointsAreCountedForTheSegment() {
        var recorder = TripRecorder(timezoneID: tz)
        recorder.startManualRecording(at: t0)
        var noisy = DriveBuilder(start: t0)
        noisy.drive(speedMps: 15, seconds: 30, accuracyM: 500)
        #expect(feed(noisy.points, into: &recorder).isEmpty)
        #expect(recorder.stopRecording(at: t0.addingTimeInterval(30)) == .tripDiscarded(.tooBrief))
        #expect(recorder.lastEndCause == .manualStop)
        #expect(recorder.lastSegment?.points == 0)
        #expect(recorder.lastSegment?.rejectedPoints == 30)
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
        #expect(recorder.lastEndCause == .gapSplit)
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
        if let output = recorder.stopRecording(at: t0.addingTimeInterval(200)) { outputs.append(output) }
        guard let trip = finalizedTrip(in: outputs) else {
            Issue.record("manual stop after a real drive must finalize")
            return
        }
        #expect(trip.source == .manual)
        #expect(abs(trip.distanceM - 199 * 10) < 199 * 10 * 0.01)
    }

    @Test func liveTrackExposesTheCurrentBuffer() {
        var recorder = TripRecorder(timezoneID: tz)
        #expect(recorder.liveTrack.isEmpty)
        #expect(recorder.recordingStartedAt == nil)
        _ = recorder.ingest(motion: automotive(t0))
        var builder = DriveBuilder(start: t0)
        builder.drive(speedMps: 15, seconds: 40)
        _ = feed(builder.points, into: &recorder)
        #expect(recorder.state == .recording)
        #expect(recorder.recordingStartedAt == t0)
        #expect(recorder.liveTrack.count == 40)
    }

    @Test func manualStopWithNothingRecordedDiscards() {
        var recorder = TripRecorder(timezoneID: tz)
        recorder.startManualRecording(at: t0)
        let output = recorder.stopRecording(at: t0)
        #expect(output == .tripDiscarded(.tooBrief))
        #expect(recorder.stopRecording(at: t0) == nil) // already idle
    }

    // MARK: Pause and resume (D-069)

    /// Drives 300 s, pauses for 20 minutes, drives 300 s more, parks.
    /// Returns the outputs and the recorder for the caller to inspect.
    private func drivePauseDrive(
        pauseSeconds: TimeInterval,
        resumeEastOffsetM: Double = 0
    ) -> (outputs: [TripRecorder.Output], recorder: TripRecorder) {
        var recorder = TripRecorder(timezoneID: tz)
        recorder.startManualRecording(at: t0)
        var first = DriveBuilder(start: t0)
        first.drive(speedMps: 15, seconds: 300)
        var outputs = feed(first.points, into: &recorder)

        // Bound first throughout: `#expect` wraps a bare call in a
        // closure whose receiver is immutable, and these are mutating.
        let pausedAt = t0.addingTimeInterval(299)
        let didPause = recorder.pauseRecording(at: pausedAt)
        #expect(didPause)
        let resumedAt = pausedAt.addingTimeInterval(pauseSeconds)
        let didResume = recorder.resumeRecording(at: resumedAt)
        #expect(didResume)

        var second = DriveBuilder(start: resumedAt)
        second.eastMeters = first.eastMeters + resumeEastOffsetM
        second.drive(speedMps: 15, seconds: 300)
        second.drive(speedMps: 0, seconds: 200)
        outputs += feed(second.points, into: &recorder)
        return (outputs, recorder)
    }

    @Test func pausingStopsTheClockAndResumingContinuesTheSameTrip() {
        let (outputs, recorder) = drivePauseDrive(pauseSeconds: 1_200)

        // One drive, not two: the only output in the whole sequence is
        // the single finalize at the end. A pause is not a gap in the
        // location stream, and nothing was discarded along the way.
        #expect(outputs.count == 1)
        #expect(recorder.lastEndCause == .idleTimeout)
        guard let trip = finalizedTrip(in: outputs) else {
            Issue.record("a paused-and-resumed drive must finalize as one trip")
            return
        }
        #expect(trip.startedAt == t0)
        #expect(trip.endedAt == t0.addingTimeInterval(1_798))
        // The wall clock ran 1798 s; 1200 of them were the driver's to
        // exclude, so the drive took 598 s and says so.
        #expect(trip.elapsedIncludingPauses == 1_798)
        #expect(trip.pausedTime == 1_200)
        #expect(trip.duration == 598)
        // 299 one-second hops at 15 m/s on each side of the pause.
        #expect(abs(trip.distanceM - 2 * 299 * 15) < 2 * 299 * 15 * 0.01)
        // Exactly one pair of samples is dropped — the one the pause sits
        // in. Dropping the pair that *ends* where the pause begins as
        // well would lose the last second driven before it, and 597 here
        // is what that bug looks like.
        #expect(trip.movingTime == 598)
    }

    /// The pause is longer than `gapSplitDuration`, which is what ends a
    /// trip when the location stream dies. The driver's own pause must
    /// not look like that.
    @Test func aPauseLongerThanTheGapSplitDoesNotSplitTheTrip() {
        let (outputs, recorder) = drivePauseDrive(pauseSeconds: 3_600)
        #expect(!outputs.contains { $0 == .tripDiscarded(.tooBrief) })
        #expect(recorder.lastEndCause != .gapSplit)
        guard let trip = finalizedTrip(in: outputs) else {
            Issue.record("an hour-long pause must not split the drive")
            return
        }
        #expect(trip.pausedTime == 3_600)
        #expect(trip.duration == 598)
    }

    /// Whatever happened while paused is not the drive — including the
    /// two kilometres the driver covered getting there.
    @Test func groundCoveredWhilePausedIsNotCounted() {
        let (outputs, _) = drivePauseDrive(pauseSeconds: 600, resumeEastOffsetM: 2_000)
        guard let trip = finalizedTrip(in: outputs) else {
            Issue.record("expected a finalized trip")
            return
        }
        // Two driven stretches only: the 2 km jump across the pause adds
        // neither distance nor moving time — and nothing either side of
        // it is lost with it.
        #expect(abs(trip.distanceM - 2 * 299 * 15) < 2 * 299 * 15 * 0.01)
        #expect(trip.movingTime == 598)
    }

    @Test func nothingReachesAPausedRecorder() {
        var recorder = TripRecorder(timezoneID: tz)
        recorder.startManualRecording(at: t0)
        var driven = DriveBuilder(start: t0)
        driven.drive(speedMps: 15, seconds: 300)
        #expect(feed(driven.points, into: &recorder).isEmpty)
        let didPause = recorder.pauseRecording(at: t0.addingTimeInterval(299))
        #expect(didPause)
        #expect(recorder.state == .paused)
        #expect(recorder.isPaused)

        // Walking into the shop is the reason to pause, so pedestrian
        // motion must not end the drive...
        let walking = TripRecorder.MotionSample(
            kind: .walking, confidence: .high, timestamp: t0.addingTimeInterval(400)
        )
        #expect(recorder.ingest(motion: walking) == nil)
        // ...and neither must ten minutes of standing still, which is far
        // past the idle window that ends a running drive.
        var parked = DriveBuilder(start: t0.addingTimeInterval(400))
        parked.eastMeters = driven.eastMeters
        parked.drive(speedMps: 0, seconds: 600)
        #expect(feed(parked.points, into: &recorder).isEmpty)

        #expect(recorder.state == .paused)
        // Not one sample kept: the driver said this is not the drive.
        #expect(recorder.liveTrack.count == 300)
        #expect(recorder.pausedSeconds(at: t0.addingTimeInterval(1_299)) == 1_000)
        #expect(recorder.drivingElapsed(at: t0.addingTimeInterval(1_299)) == 299)
    }

    /// Pause, then Stop. The drive ended when the clock did; the seconds
    /// the phone sat paused are not subtracted from it, or a real drive
    /// could be shortened into a discard.
    @Test func stoppingFromPausedEndsTheDriveAtThePause() {
        var recorder = TripRecorder(timezoneID: tz)
        recorder.startManualRecording(at: t0)
        var driven = DriveBuilder(start: t0)
        driven.drive(speedMps: 15, seconds: 300)
        #expect(feed(driven.points, into: &recorder).isEmpty)
        let didPause = recorder.pauseRecording(at: t0.addingTimeInterval(299))
        #expect(didPause)

        let output = recorder.stopRecording(at: t0.addingTimeInterval(899))
        guard case .tripFinalized(let trip)? = output else {
            Issue.record("Stop from paused must finalize the drive, not discard it")
            return
        }
        #expect(recorder.lastEndCause == .manualStop)
        #expect(recorder.state == .idle)
        #expect(trip.endedAt == t0.addingTimeInterval(299))
        #expect(trip.pausedTime == 0)
        #expect(trip.duration == 299)
    }

    @Test func pauseAndResumeRefuseWhenThereIsNothingToPause() {
        var recorder = TripRecorder(timezoneID: tz)
        let pausedWhileIdle = recorder.pauseRecording(at: t0)
        #expect(!pausedWhileIdle)
        let resumedWhileIdle = recorder.resumeRecording(at: t0)
        #expect(!resumedWhileIdle)

        recorder.startManualRecording(at: t0)
        let resumedWhileRunning = recorder.resumeRecording(at: t0)
        #expect(!resumedWhileRunning, "running, not paused")

        let paused = recorder.pauseRecording(at: t0)
        #expect(paused)
        let pausedTwice = recorder.pauseRecording(at: t0)
        #expect(!pausedTwice, "already paused")
    }
}
