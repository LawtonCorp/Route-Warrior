import Foundation
import Testing
@testable import RouteWarriorKit

/// Synthetic 1 Hz tracks with hand-placed halts; expected durations and
/// causes follow directly from the constructed timestamps.
struct StopDetectorTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    /// `segments` is (speedMps, seconds); points sit 1 s apart at a fixed
    /// per-second longitude step while moving so halts have a fixed spot.
    private func track(_ segments: [(speed: Double, seconds: Int)]) -> [TrackPoint] {
        var points: [TrackPoint] = []
        var time = t0
        var east = 0.0
        for segment in segments {
            for _ in 0..<segment.seconds {
                points.append(TrackPoint(
                    coordinate: Coordinate(latitude: 0, longitude: east / 111_195.08),
                    timestamp: time,
                    speedMps: segment.speed,
                    horizontalAccuracyM: 5
                ))
                east += segment.speed
                time = time.addingTimeInterval(1)
            }
        }
        return points
    }

    @Test func oneSecondJitterIsNotAStop() {
        let events = StopDetector.stopEvents(in: track([(15, 30), (0, 2), (15, 30)]))
        // Two zero-speed samples span 1 s — under the 2 s floor.
        #expect(events.isEmpty)
    }

    @Test func briefHaltReadsAsStopSign() {
        let events = StopDetector.stopEvents(in: track([(15, 30), (0, 5), (15, 30)]))
        #expect(events.count == 1)
        #expect(events.first?.cause == .stopSign)
        #expect(events.first?.duration == 4)
        #expect(events.first?.startedAt == t0.addingTimeInterval(30))
    }

    @Test func mediumHaltReadsAsSignal() {
        let events = StopDetector.stopEvents(in: track([(15, 30), (0, 31), (15, 30)]))
        #expect(events.count == 1)
        #expect(events.first?.cause == .signal)
        #expect(events.first?.duration == 30)
    }

    @Test func longHaltReadsAsTrafficQueue() {
        let events = StopDetector.stopEvents(in: track([(15, 30), (0, 121), (15, 30)]))
        #expect(events.count == 1)
        #expect(events.first?.cause == .trafficQueue)
        #expect(events.first?.duration == 120)
    }

    @Test func boundaryDurationsUseInclusiveUpperBounds() {
        // 9 zero-speed samples = 8 s: still a stop sign.
        #expect(StopDetector.stopEvents(in: track([(15, 10), (0, 9), (15, 10)])).first?.cause == .stopSign)
        // 91 samples = 90 s: still a signal.
        #expect(StopDetector.stopEvents(in: track([(15, 10), (0, 91), (15, 10)])).first?.cause == .signal)
    }

    @Test func multipleHaltsComeBackInOrderAtTheirLocations() {
        let events = StopDetector.stopEvents(in: track([
            (15, 60), (0, 5), (15, 60), (0, 40), (15, 60),
        ]))
        #expect(events.map(\.cause) == [.stopSign, .signal])
        #expect(events[0].startedAt < events[1].startedAt)
        // Each halt's centroid sits where the car stopped: 60×15 m east,
        // then (60+60)×15 m east of the start.
        let metersPerDegree = 111_195.08
        #expect(abs(events[0].coordinate.longitude * metersPerDegree - 900) < 1)
        #expect(abs(events[1].coordinate.longitude * metersPerDegree - 1800) < 1)
    }

    @Test func trailingHaltAtTrackEndIsClosed() {
        let events = StopDetector.stopEvents(in: track([(15, 30), (0, 10)]))
        #expect(events.count == 1)
        #expect(events.first?.duration == 9)
    }

    @Test func invalidSpeedSamplesAreNotHalts() {
        var points = track([(15, 30)])
        var time = points.last!.timestamp.addingTimeInterval(1)
        for _ in 0..<10 {
            points.append(TrackPoint(
                coordinate: points.last!.coordinate,
                timestamp: time,
                speedMps: -1,
                horizontalAccuracyM: 5
            ))
            time = time.addingTimeInterval(1)
        }
        #expect(StopDetector.stopEvents(in: points).isEmpty)
        #expect(StopDetector.stopEvents(in: []).isEmpty)
    }
}
