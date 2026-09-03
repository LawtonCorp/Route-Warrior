import Foundation

/// The live race against your own history (FR-15): project the current
/// position onto the variant's line, look up when the reference got that
/// far, and report ahead/behind. Pure functions of (polyline, profile,
/// sample) — the Live Activity just renders the result.
public enum GhostRace {
    /// A distance-along-route → elapsed-time curve built from history.
    public struct ReferenceProfile: Sendable, Equatable {
        /// Monotonically increasing (alongMeters, elapsedSeconds) samples.
        public var samples: [Sample]

        public struct Sample: Sendable, Equatable {
            public var alongMeters: Double
            public var elapsed: TimeInterval

            public init(alongMeters: Double, elapsed: TimeInterval) {
                self.alongMeters = alongMeters
                self.elapsed = elapsed
            }
        }

        /// A curve built directly from samples — used for references
        /// that are not a driven trip, such as a provider's flat ETA pace.
        public init(samples: [Sample]) {
            self.samples = samples
        }

        /// Profile of a single reference trip (the personal best, say)
        /// against the variant's line. Nil when the trip cannot be
        /// projected (too few points).
        public init?(trip: Trip, along polyline: Polyline) {
            var built: [Sample] = []
            for point in trip.points {
                guard let hit = polyline.nearestPoint(to: point.coordinate) else { continue }
                let elapsed = point.timestamp.timeIntervalSince(trip.startedAt)
                // Keep the curve monotonic: GPS scatter that projects
                // backward teaches nothing about pace.
                if let last = built.last, hit.alongMeters <= last.alongMeters { continue }
                built.append(Sample(alongMeters: hit.alongMeters, elapsed: elapsed))
            }
            guard built.count >= 2 else { return nil }
            self.samples = built
        }

        /// The bucket-average reference: mean elapsed across several trips
        /// at evenly spaced distances. Trips that cannot be profiled are
        /// skipped; nil when none survive.
        public init?(averaging trips: [Trip], along polyline: Polyline, sampleCount: Int = 64) {
            let profiles = trips.compactMap { ReferenceProfile(trip: $0, along: polyline) }
            guard !profiles.isEmpty, sampleCount >= 2 else { return nil }
            let length = polyline.lengthMeters
            guard length > 0 else { return nil }
            var built: [Sample] = []
            for i in 0..<sampleCount {
                let distance = length * Double(i) / Double(sampleCount - 1)
                let elapsed = profiles.compactMap { $0.elapsed(atAlongMeters: distance) }
                guard !elapsed.isEmpty else { continue }
                built.append(Sample(
                    alongMeters: distance,
                    elapsed: elapsed.reduce(0, +) / Double(elapsed.count)
                ))
            }
            guard built.count >= 2 else { return nil }
            self.samples = built
        }

        /// Linear interpolation on the curve; clamps to the ends.
        public func elapsed(atAlongMeters distance: Double) -> TimeInterval? {
            guard let first = samples.first, let last = samples.last else { return nil }
            if distance <= first.alongMeters { return first.elapsed }
            if distance >= last.alongMeters { return last.elapsed }
            for i in 1..<samples.count where samples[i].alongMeters >= distance {
                let a = samples[i - 1]
                let b = samples[i]
                let span = b.alongMeters - a.alongMeters
                let t = span > 0 ? (distance - a.alongMeters) / span : 0
                return a.elapsed + t * (b.elapsed - a.elapsed)
            }
            return last.elapsed
        }
    }

    public struct Status: Sendable, Equatable {
        /// Positive = ahead of the reference by this many seconds.
        public var aheadSeconds: Double
        public var distanceAlongM: Double
        public var routeLengthM: Double
        public var myElapsed: TimeInterval
        public var referenceElapsed: TimeInterval
    }

    /// Where the race stands right now. Nil when the position cannot be
    /// projected or the reference has no curve there.
    public static func status(
        myElapsed: TimeInterval,
        position: Coordinate,
        along polyline: Polyline,
        reference: ReferenceProfile
    ) -> Status? {
        guard let hit = polyline.nearestPoint(to: position),
              let referenceElapsed = reference.elapsed(atAlongMeters: hit.alongMeters)
        else { return nil }
        return Status(
            aheadSeconds: referenceElapsed - myElapsed,
            distanceAlongM: hit.alongMeters,
            routeLengthM: polyline.lengthMeters,
            myElapsed: myElapsed,
            referenceElapsed: referenceElapsed
        )
    }
}
