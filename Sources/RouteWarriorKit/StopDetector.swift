import Foundation

/// Finds the halts in a recorded track and gives each a first-pass cause
/// from its duration alone (SPEC §2.3). The OSM-aware reclassification —
/// "this halt sits 12 m from a mapped stop sign" — arrives with the M3
/// intersection inventory; until then causes are the honest duration prior.
public enum StopDetector {
    public struct Config: Sendable {
        /// At or below this speed a point counts as halted.
        public var maxStopSpeedMps: Double = 1.0
        /// Halts briefer than this are GPS jitter, not stops.
        public var minStopDuration: TimeInterval = 2
        /// Duration at or below which a halt reads as a stop sign.
        public var stopSignMaxDuration: TimeInterval = 8
        /// Duration at or below which a halt reads as a signal;
        /// anything longer reads as a traffic queue.
        public var signalMaxDuration: TimeInterval = 90

        public init() {}
    }

    public static func stopEvents(in points: [TrackPoint], config: Config = Config()) -> [StopEvent] {
        var events: [StopEvent] = []
        var haltStart: Int?

        func close(_ start: Int, endingBefore end: Int) {
            let halt = points[start..<end]
            guard let first = halt.first, let last = halt.last else { return }
            let duration = last.timestamp.timeIntervalSince(first.timestamp)
            guard duration >= config.minStopDuration else { return }

            let count = Double(halt.count)
            let centroid = Coordinate(
                latitude: halt.reduce(0) { $0 + $1.coordinate.latitude } / count,
                longitude: halt.reduce(0) { $0 + $1.coordinate.longitude } / count
            )
            let cause: StopEvent.Cause
            if duration <= config.stopSignMaxDuration {
                cause = .stopSign
            } else if duration <= config.signalMaxDuration {
                cause = .signal
            } else {
                cause = .trafficQueue
            }
            events.append(StopEvent(
                coordinate: centroid,
                startedAt: first.timestamp,
                duration: duration,
                cause: cause
            ))
        }

        for (i, point) in points.enumerated() {
            let halted = point.speedMps >= 0 && point.speedMps <= config.maxStopSpeedMps
            if halted {
                if haltStart == nil { haltStart = i }
            } else if let start = haltStart {
                close(start, endingBefore: i)
                haltStart = nil
            }
        }
        if let start = haltStart {
            close(start, endingBefore: points.count)
        }
        return events
    }
}
