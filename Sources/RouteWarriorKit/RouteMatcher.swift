import Foundation

/// Assigns a finalized trip its places, its route variant, and its
/// followed-the-plan label (SPEC §2.3, FR-7/FR-9). Pure: callers pass the
/// known places and existing variants in, and get the updated trip plus any
/// newly founded variant back.
public enum RouteMatcher {
    public struct Config: Sendable {
        /// Mean deviation at or under which a trip belongs to a variant.
        public var variantMatchThresholdM: Double = 150
        /// Mean deviation at or under which a trip followed the snapshot.
        public var followedPlanThresholdM: Double = 100
        /// Resampling density for shape comparison.
        public var samples: Int = 64

        public init() {}
    }

    public struct Result: Sendable, Equatable {
        /// The trip with origin/destination/variant/followedPlan filled in.
        public var trip: Trip
        /// Set when no existing variant matched and the trip founded one.
        public var newVariant: RouteVariant?
        /// The variant the trip landed in (existing or new), if any.
        public var variantID: UUID?
    }

    /// The first place whose geofence contains the coordinate.
    public static func place(containing coordinate: Coordinate, in places: [Place]) -> Place? {
        places.first { $0.contains(coordinate) }
    }

    public static func assign(
        trip: Trip,
        places: [Place],
        variants: [RouteVariant],
        snapshot: PlanSnapshot? = nil,
        config: Config = Config()
    ) -> Result {
        var updated = trip
        let track = Polyline(coordinates: trip.points.map(\.coordinate))

        let origin = trip.points.first.flatMap { place(containing: $0.coordinate, in: places) }
        let destination = trip.points.last.flatMap { place(containing: $0.coordinate, in: places) }
        updated.originPlaceID = origin?.id
        updated.destinationPlaceID = destination?.id

        if let snapshot,
           let deviation = track.symmetricMeanDeviation(to: snapshot.polyline, samples: config.samples) {
            updated.followedPlan = deviation <= config.followedPlanThresholdM
        }

        // A variant needs both endpoints to mean anything: "my way to school"
        // is defined by where it starts and ends.
        guard let origin, let destination else {
            return Result(trip: updated, newVariant: nil, variantID: nil)
        }

        let candidates = variants.filter {
            $0.originPlaceID == origin.id && $0.destinationPlaceID == destination.id
        }
        var best: (variant: RouteVariant, deviation: Double)?
        for candidate in candidates {
            guard let deviation = track.symmetricMeanDeviation(
                to: candidate.representativePolyline, samples: config.samples
            ) else { continue }
            if best == nil || deviation < best!.deviation {
                best = (candidate, deviation)
            }
        }

        if let best, best.deviation <= config.variantMatchThresholdM {
            updated.variantID = best.variant.id
            return Result(trip: updated, newVariant: nil, variantID: best.variant.id)
        }

        guard track.coordinates.count >= 2 else {
            return Result(trip: updated, newVariant: nil, variantID: nil)
        }
        let variant = RouteVariant(
            originPlaceID: origin.id,
            destinationPlaceID: destination.id,
            representativePolyline: track.resampled(to: config.samples),
            autoName: nextAutoName(after: candidates.count),
            tripCount: 1
        )
        updated.variantID = variant.id
        return Result(trip: updated, newVariant: variant, variantID: variant.id)
    }

    /// "Route A", "Route B", … — street-name auto-naming ("via Maple Ave")
    /// needs map data and arrives with M3's reverse geocoding in the app.
    static func nextAutoName(after existingCount: Int) -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let index = existingCount % letters.count
        let letter = letters[letters.index(letters.startIndex, offsetBy: index)]
        let generation = existingCount / letters.count
        return generation == 0 ? "Route \(letter)" : "Route \(letter)\(generation + 1)"
    }
}
