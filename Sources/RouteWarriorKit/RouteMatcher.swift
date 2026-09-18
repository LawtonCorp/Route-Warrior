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
        /// How far outside its own geofence a place may still claim an
        /// endpoint (D-081). A place's fence is 75 m by default and a
        /// drive's last kept point is its last *moving* one, so crawling
        /// into a car park, a garage that eats the signal, or a space at
        /// the far end of a lot all end a drive outside the fence of the
        /// place it plainly reached.
        public var endpointToleranceM: Double = 200
        /// How far from the destination the driver named a drive may end
        /// and still be counted as having arrived there. Wider than the
        /// tolerance above because it is not a guess: the driver said so.
        /// Not unlimited — saying "home" and then driving to the coast
        /// makes the statement wrong, not the drive.
        public var statedDestinationToleranceM: Double = 500

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

    /// The place an endpoint belongs to (D-081): inside a geofence
    /// first, then the nearest place within `tolerance` of it.
    ///
    /// Strictly inside is certainty and is tried first, so a place never
    /// loses an endpoint that is genuinely in it. The fallback exists
    /// because the endpoints are where the geofence is least reliable —
    /// a drive ends at its last moving point, which can be a hundred
    /// metres short of the door.
    static func place(
        at coordinate: Coordinate, in places: [Place], tolerance: Double
    ) -> Place? {
        if let inside = place(containing: coordinate, in: places) { return inside }
        return nearest(to: coordinate, in: places, within: tolerance)
    }

    /// The nearest place within `within` metres, or nil. Ties cannot
    /// happen in practice and resolve by list order if they do.
    static func nearest(
        to coordinate: Coordinate, in places: [Place], within: Double
    ) -> Place? {
        places
            .map { ($0, Geo.distanceMeters(from: $0.coordinate, to: coordinate)) }
            .filter { $0.1 <= within }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// The destination the driver named for this drive, honoured when
    /// the track itself cannot name one (D-081). A stated destination is
    /// evidence — the driver typed it or tapped it — but the drive has
    /// to have ended somewhere near it, or the statement describes an
    /// intention that the drive did not carry out.
    static func statedDestination(
        _ statedID: UUID?, endingAt end: Coordinate?, in places: [Place], tolerance: Double
    ) -> Place? {
        guard let statedID, let end,
              let place = places.first(where: { $0.id == statedID }),
              Geo.distanceMeters(from: place.coordinate, to: end) <= tolerance
        else { return nil }
        return place
    }

    /// - Parameter statedDestinationID: the place the driver named for
    ///   this drive — picked from the departure notification, or the
    ///   destination a planned drive set off for (D-081). Used only when
    ///   the track cannot name a destination itself.
    public static func assign(
        trip: Trip,
        places: [Place],
        variants: [RouteVariant],
        snapshot: PlanSnapshot? = nil,
        altSnapshot: PlanSnapshot? = nil,
        statedDestinationID: UUID? = nil,
        config: Config = Config()
    ) -> Result {
        var updated = trip
        let track = Polyline(coordinates: trip.points.map(\.coordinate))

        let start = trip.points.first?.coordinate
        let end = trip.points.last?.coordinate
        let origin = start.flatMap {
            place(at: $0, in: places, tolerance: config.endpointToleranceM)
        }
        let destination = end.flatMap {
            place(at: $0, in: places, tolerance: config.endpointToleranceM)
        } ?? statedDestination(
            statedDestinationID, endingAt: end, in: places,
            tolerance: config.statedDestinationToleranceM
        )
        updated.originPlaceID = origin?.id
        updated.destinationPlaceID = destination?.id

        if let snapshot,
           let deviation = track.symmetricMeanDeviation(to: snapshot.polyline, samples: config.samples) {
            updated.followedPlan = deviation <= config.followedPlanThresholdM
        }
        if let altSnapshot,
           let deviation = track.symmetricMeanDeviation(to: altSnapshot.polyline, samples: config.samples) {
            updated.followedAltPlan = deviation <= config.followedPlanThresholdM
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
