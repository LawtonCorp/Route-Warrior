import Foundation

/// Predicts where a departing drive is headed, from history alone
/// (SPEC §2.3, FR-6, D-010): P(destination | origin, weekday, 30-minute
/// slot, initial bearing), as a smoothed frequency table with backoff for
/// sparse cells. Confidence is the top-1 probability; `advice` applies the
/// snapshot thresholds.
public struct DestinationPredictor: Sendable {
    public struct Config: Sendable {
        /// Top-1 probability at or above which one snapshot suffices.
        public var highConfidence: Double = 0.6
        /// Top-1 probability at or above which two snapshots are taken;
        /// below it, none.
        public var lowConfidence: Double = 0.35
        /// A context cell with fewer trips than this backs off to a
        /// coarser one.
        public var minCellSamples: Int = 3
        /// Bearing bucket width in degrees.
        public var bearingBucketDegrees: Double = 45
        /// How far into the drive the initial bearing is measured.
        public var bearingDistanceM: Double = 300

        public init() {}
    }

    public struct Prediction: Sendable, Equatable {
        public var destinationPlaceID: UUID
        public var probability: Double
    }

    public enum Advice: Sendable, Equatable {
        case snapshotOne(Prediction)
        case snapshotTwo(Prediction, Prediction)
        case none
    }

    private struct Observation {
        var origin: UUID?
        var weekday: Int
        var slot: Int
        var bearingBucket: Int?
        var destination: UUID
    }

    private let observations: [Observation]
    private let config: Config

    /// Builds the table from recorded history. Trips without a destination
    /// place, or excluded from stats, teach nothing.
    public init(trips: [Trip], config: Config = Config()) {
        self.config = config
        self.observations = trips.compactMap { trip in
            guard let destination = trip.destinationPlaceID, !trip.excludedFromStats else { return nil }
            let (weekday, slot) = Self.context(for: trip.startedAt, timezoneID: trip.timezoneID)
            return Observation(
                origin: trip.originPlaceID,
                weekday: weekday,
                slot: slot,
                bearingBucket: Self.initialBearing(of: trip.points, overMeters: config.bearingDistanceM)
                    .map { Self.bucket(forBearing: $0, width: config.bearingBucketDegrees) },
                destination: destination
            )
        }
    }

    // MARK: Prediction

    /// Ranked destinations for a departure. `initialBearingDegrees` is nil
    /// at standstill; re-query once the first few hundred meters reveal it.
    public func predictions(
        fromOrigin origin: UUID?,
        at date: Date,
        timezoneID: String,
        initialBearingDegrees: Double? = nil
    ) -> [Prediction] {
        let (weekday, slot) = Self.context(for: date, timezoneID: timezoneID)
        let originMatches = origin != nil ? observations.filter { $0.origin == origin } : observations
        guard !originMatches.isEmpty else { return [] }

        // Backoff ladder: exact weekday+slot cell → same slot any weekday →
        // everything from this origin. The first rung with enough samples
        // wins.
        let ladders: [[Observation]] = [
            originMatches.filter { $0.weekday == weekday && abs($0.slot - slot) <= 1 },
            originMatches.filter { abs($0.slot - slot) <= 1 },
            originMatches,
        ]
        var cell = ladders.first { $0.count >= config.minCellSamples } ?? originMatches

        if let bearing = initialBearingDegrees {
            let bucket = Self.bucket(forBearing: bearing, width: config.bearingBucketDegrees)
            let bucketCount = Int((360 / config.bearingBucketDegrees).rounded())
            let matching = cell.filter {
                guard let b = $0.bearingBucket else { return false }
                let distance = abs(b - bucket)
                return min(distance, bucketCount - distance) <= 1
            }
            if !matching.isEmpty { cell = matching }
        }

        var counts: [UUID: Int] = [:]
        for observation in cell {
            counts[observation.destination, default: 0] += 1
        }
        let distinct = Set(observations.map(\.destination)).count
        let total = cell.count
        // Laplace smoothing over every destination ever seen, so one lone
        // observation never claims certainty.
        return counts
            .map { destination, count in
                Prediction(
                    destinationPlaceID: destination,
                    probability: Double(count + 1) / Double(total + distinct)
                )
            }
            .sorted {
                $0.probability != $1.probability
                    ? $0.probability > $1.probability
                    : $0.destinationPlaceID.uuidString < $1.destinationPlaceID.uuidString
            }
    }

    /// FR-6: high confidence → one snapshot; medium → two; low → none.
    public func advice(
        fromOrigin origin: UUID?,
        at date: Date,
        timezoneID: String,
        initialBearingDegrees: Double? = nil
    ) -> Advice {
        let ranked = predictions(
            fromOrigin: origin,
            at: date,
            timezoneID: timezoneID,
            initialBearingDegrees: initialBearingDegrees
        )
        guard let top = ranked.first else { return .none }
        if top.probability >= config.highConfidence { return .snapshotOne(top) }
        if top.probability >= config.lowConfidence {
            if ranked.count >= 2 { return .snapshotTwo(top, ranked[1]) }
            return .snapshotOne(top)
        }
        return .none
    }

    // MARK: Context helpers

    /// (weekday 1...7 Sunday-first, 30-minute slot 0...47) in the trip's
    /// own timezone — the 7:30 school run is 7:30 wherever it happened.
    static func context(for date: Date, timezoneID: String) -> (weekday: Int, slot: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezoneID) ?? .init(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let slot = (components.hour ?? 0) * 2 + ((components.minute ?? 0) >= 30 ? 1 : 0)
        return (components.weekday ?? 1, slot)
    }

    /// Bearing from the first point to the first point at least
    /// `overMeters` along the track.
    public static func initialBearing(of points: [TrackPoint], overMeters: Double) -> Double? {
        guard let first = points.first else { return nil }
        for point in points.dropFirst()
        where Geo.distanceMeters(from: first.coordinate, to: point.coordinate) >= overMeters {
            return Geo.bearingDegrees(from: first.coordinate, to: point.coordinate)
        }
        return nil
    }

    static func bucket(forBearing bearing: Double, width: Double) -> Int {
        let normalized = bearing.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        return Int(positive / width)
    }
}
