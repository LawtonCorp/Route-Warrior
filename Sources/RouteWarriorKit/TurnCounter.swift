import Foundation

/// One turn along a line: where it was, how sharp, and which way.
public struct Turn: Sendable, Equatable, Codable {
    public enum Direction: String, Sendable, Codable, CaseIterable {
        case left
        case right
        /// A reversal — sharper than `TurnCounter.Config.uTurnDegrees`.
        case uTurn
    }

    /// The sharpest point of the turn.
    public var coordinate: Coordinate
    /// Arc-length position of that point from the start of the line.
    public var alongMeters: Double
    /// Heading change at the sharpest point, degrees, clockwise positive.
    /// A right turn is positive, a left turn negative.
    public var degrees: Double
    public var direction: Direction

    public init(coordinate: Coordinate, alongMeters: Double, degrees: Double, direction: Direction) {
        self.coordinate = coordinate
        self.alongMeters = alongMeters
        self.degrees = degrees
        self.direction = direction
    }
}

/// How many times a route turns, by direction. Left turns cross traffic
/// and wait for gaps (in America — swap for right in left-driving
/// countries), so they cost time the way a stop sign does; the counts are
/// kept apart so the expensive kind can be read on its own.
public struct TurnCount: Sendable, Equatable, Hashable, Codable {
    public var left: Int
    public var right: Int
    public var uTurn: Int

    public init(left: Int = 0, right: Int = 0, uTurn: Int = 0) {
        self.left = left
        self.right = right
        self.uTurn = uTurn
    }

    public static let zero = TurnCount()

    public var total: Int { left + right + uTurn }

    public init(turns: [Turn]) {
        var count = TurnCount()
        for turn in turns {
            switch turn.direction {
            case .left: count.left += 1
            case .right: count.right += 1
            case .uTurn: count.uTurn += 1
            }
        }
        self = count
    }

    /// The per-direction median of several counts — the typical drive on
    /// a route, robust to one drive whose track wandered. Nil for none.
    public static func median(of counts: [TurnCount]) -> TurnCount? {
        guard !counts.isEmpty else { return nil }
        func median(_ values: [Int]) -> Int {
            let sorted = values.sorted()
            // Even counts take the lower middle: an integer, and a count a
            // drive actually had rather than a half-turn.
            return sorted[(sorted.count - 1) / 2]
        }
        return TurnCount(
            left: median(counts.map(\.left)),
            right: median(counts.map(\.right)),
            uTurn: median(counts.map(\.uTurn))
        )
    }
}

/// Counts the turns along a line from its shape alone — no map data, so it
/// works the same on a driven track, a provider's plan and a plan's
/// alternates, and it never needs the network.
///
/// The line is resampled at a fixed step, and at each sample the heading
/// over the next `windowMeters` is compared with the heading over the
/// previous `windowMeters`. A turn begins where that change passes
/// `enterDegrees` and ends where it falls back under `exitDegrees`; its
/// sharpest point is the turn. The window is what separates a corner from
/// a bend: a 90° corner at an intersection (radius 5–25 m) swings the
/// heading by most of 90° inside 20 m either side, while a sweeping
/// highway curve of radius 100 m changes it by only about 23° — a road
/// that bends is not a road that turns.
public enum TurnCounter {
    public struct Config: Sendable {
        /// Resampling step along the line.
        public var stepMeters: Double = 5
        /// Heading is measured over this much line on each side of a
        /// point. With the default enter angle, a 90° corner counts up to
        /// a radius of about 25 m (a wide suburban curb) and a long bend
        /// up to about 50 m (a tight ramp); a sweep you take at speed
        /// does not.
        public var windowMeters: Double = 20
        /// Heading change that opens a turn.
        public var enterDegrees: Double = 45
        /// Heading change that closes it — lower than `enterDegrees` so a
        /// corner is one turn, not several as the value hovers.
        public var exitDegrees: Double = 20
        /// A turn at least this sharp is a reversal.
        public var uTurnDegrees: Double = 135
        /// Track points slower than this are dropped before counting: a
        /// phone at a red light wanders a few metres in every direction,
        /// which reads as turning without going anywhere. Unknown speed
        /// (negative) is kept — a gap in speed is not a halt.
        public var minSpeedMps: Double = 1.0
        /// Track points with a worse horizontal accuracy are dropped.
        public var maxAccuracyMeters: Double = 50
        /// Consecutive kept points closer than this collapse into one.
        public var minSpacingMeters: Double = 2

        public init() {}
    }

    // MARK: Lines

    /// Every turn along `polyline`, in order of arc length.
    public static func turns(along polyline: Polyline, config: Config = Config()) -> [Turn] {
        let line = spaced(polyline, config: config)
        let length = line.lengthMeters
        guard line.coordinates.count >= 2, length > 2 * config.windowMeters, config.stepMeters > 0 else {
            return []
        }
        let sampleCount = max(2, Int((length / config.stepMeters).rounded()) + 1)
        let samples = line.resampled(to: sampleCount).coordinates
        let step = length / Double(sampleCount - 1)
        let window = max(1, Int((config.windowMeters / step).rounded()))
        guard samples.count > 2 * window else { return [] }

        var turns: [Turn] = []
        var open: (peak: Double, index: Int)?

        func close() {
            guard let turn = open else { return }
            turns.append(Turn(
                coordinate: samples[turn.index],
                alongMeters: Double(turn.index) * step,
                degrees: turn.peak,
                direction: direction(of: turn.peak, config: config)
            ))
            open = nil
        }

        for index in window..<(samples.count - window) {
            let inbound = Geo.bearingDegrees(from: samples[index - window], to: samples[index])
            let outbound = Geo.bearingDegrees(from: samples[index], to: samples[index + window])
            let change = signedChange(from: inbound, to: outbound)

            if let current = open {
                let sameWay = (change >= 0) == (current.peak >= 0)
                if sameWay, abs(change) >= config.exitDegrees {
                    if abs(change) > abs(current.peak) {
                        open = (peak: change, index: index)
                    }
                    continue
                }
                close()
            }
            if abs(change) >= config.enterDegrees {
                open = (peak: change, index: index)
            }
        }
        close()
        return turns
    }

    public static func count(along polyline: Polyline, config: Config = Config()) -> TurnCount {
        TurnCount(turns: turns(along: polyline, config: config))
    }

    // MARK: Trips

    /// The trip's track with halted and poorly fixed samples removed —
    /// the shape the car actually drew, not the shape the phone drew
    /// while the car was waiting.
    public static func track(of trip: Trip, config: Config = Config()) -> Polyline {
        let kept = trip.points.filter { point in
            let moving = point.speedMps < 0 || point.speedMps >= config.minSpeedMps
            let fixed = point.horizontalAccuracyM < 0 || point.horizontalAccuracyM <= config.maxAccuracyMeters
            return moving && fixed
        }
        return Polyline(coordinates: kept.map(\.coordinate))
    }

    public static func count(for trip: Trip, config: Config = Config()) -> TurnCount {
        count(along: track(of: trip, config: config), config: config)
    }

    /// The typical count over several drives of one route: the median per
    /// direction, ignoring trips too short to have a shape. Nil when no
    /// trip can be counted.
    public static func typical(for trips: [Trip], config: Config = Config()) -> TurnCount? {
        let counts = trips.compactMap { trip -> TurnCount? in
            let track = track(of: trip, config: config)
            guard track.coordinates.count >= 2, track.lengthMeters > 2 * config.windowMeters else { return nil }
            return count(along: track, config: config)
        }
        return TurnCount.median(of: counts)
    }

    // MARK: Helpers

    /// `to − from` folded into (−180, 180]: positive is clockwise.
    static func signedChange(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta <= -180 { delta += 360 }
        return delta
    }

    static func direction(of degrees: Double, config: Config) -> Turn.Direction {
        if abs(degrees) >= config.uTurnDegrees { return .uTurn }
        return degrees > 0 ? .right : .left
    }

    /// Drops consecutive points closer than `minSpacingMeters`, so a burst
    /// of near-identical fixes cannot pile up arc length in one spot.
    static func spaced(_ polyline: Polyline, config: Config) -> Polyline {
        guard let first = polyline.coordinates.first else { return polyline }
        var kept = [first]
        for coordinate in polyline.coordinates.dropFirst()
        where Geo.distanceMeters(from: kept[kept.count - 1], to: coordinate) >= config.minSpacingMeters {
            kept.append(coordinate)
        }
        return Polyline(coordinates: kept)
    }
}
