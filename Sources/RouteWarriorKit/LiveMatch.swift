import Foundation

public extension Polyline {
    /// One-directional mean deviation: how far this line's resampled points
    /// sit from `other`. Unlike the symmetric metric, a partial drive can
    /// be held against a full variant line — the not-yet-driven remainder
    /// of the variant doesn't count against the match.
    func meanDeviation(to other: Polyline, samples: Int = 64) -> Double? {
        guard coordinates.count >= 2, other.coordinates.count >= 2 else { return nil }
        let sampled = resampled(to: samples).coordinates
        var total = 0.0
        for point in sampled {
            guard let hit = other.nearestPoint(to: point) else { return nil }
            total += hit.distanceMeters
        }
        return total / Double(sampled.count)
    }
}

public extension RouteMatcher {
    struct LiveMatch: Sendable, Equatable {
        public var variantID: UUID
        public var deviationM: Double
    }

    /// Recognizes which variant an in-progress drive is on, so the ghost
    /// race can pick its reference (FR-15). Requires enough driven track to
    /// mean anything; returns nil until the drive commits to a known shape.
    static func liveMatch(
        partialTrack: Polyline,
        candidates: [RouteVariant],
        minTrackLengthM: Double = 800,
        config: Config = Config()
    ) -> LiveMatch? {
        guard partialTrack.lengthMeters >= minTrackLengthM else { return nil }
        var best: (variant: RouteVariant, deviation: Double)?
        for candidate in candidates {
            guard let deviation = partialTrack.meanDeviation(
                to: candidate.representativePolyline, samples: config.samples
            ) else { continue }
            if best == nil || deviation < best!.deviation {
                best = (candidate, deviation)
            }
        }
        guard let best, best.deviation <= config.variantMatchThresholdM else { return nil }
        return LiveMatch(variantID: best.variant.id, deviationM: best.deviation)
    }
}
