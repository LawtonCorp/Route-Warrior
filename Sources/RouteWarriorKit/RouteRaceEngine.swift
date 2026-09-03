import Foundation

/// Which of the driver's own routes to a destination is actually faster.
/// `VerdictEngine` answers "me versus the provider"; this answers "my way
/// versus my other way", which is the question behind four drives to
/// school by three different roads. Passenger rides are excluded by
/// `StatsEngine`, so they cannot decide a route.
public enum RouteRaceEngine {
    public struct Config: Sendable {
        /// Drives per route before a head-to-head is called. Lower than
        /// the provider verdict's floor: these are the same driver in the
        /// same car, so the only noise is traffic and the day.
        public var minSamplesPerRoute: Int = 3
        /// Median gaps inside this margin are a tie, not a win.
        public var tieMarginSeconds: Double = 30
        /// Both routes at or above this sample count → high confidence.
        public var highConfidenceSamples: Int = 8

        public init() {}
    }

    /// One route with everything the comparison needs to explain itself.
    public struct Route: Sendable, Equatable, Identifiable {
        public var id: UUID
        public var name: String
        public var stats: StatsEngine.DurationStats
        public var signalCount: Int?
        public var stopSignCount: Int?

        public init(
            id: UUID,
            name: String,
            stats: StatsEngine.DurationStats,
            signalCount: Int? = nil,
            stopSignCount: Int? = nil
        ) {
            self.id = id
            self.name = name
            self.stats = stats
            self.signalCount = signalCount
            self.stopSignCount = stopSignCount
        }

        /// Signals plus stop signs: what explains a slower route more
        /// often than distance does. Nil until the inventory is fetched.
        public var intersectionCount: Int? {
            guard let signalCount, let stopSignCount else { return nil }
            return signalCount + stopSignCount
        }
    }

    public enum Outcome: Sendable, Equatable {
        /// Nothing to race: the driver has taken one route, or none.
        case oneRouteOnly
        /// Two routes exist, but one is short of the floor.
        case collecting(drivesNeeded: Int)
        case tie(gapSeconds: Double)
        case winner(gapSeconds: Double, confidence: VerdictEngine.Confidence)
    }

    public struct Race: Sendable, Equatable {
        /// Every route with at least one counted drive, fastest median
        /// first.
        public var routes: [Route]
        public var outcome: Outcome

        public var fastest: Route? { routes.first }
        public var runnerUp: Route? { routes.count > 1 ? routes[1] : nil }
    }

    public static func race(
        variants: [RouteVariant],
        trips: [Trip],
        config: Config = Config()
    ) -> Race {
        var routes: [Route] = []
        for variant in variants {
            let mine = trips.filter { $0.variantID == variant.id }
            guard let stats = StatsEngine.durationStats(for: mine) else { continue }
            routes.append(Route(
                id: variant.id,
                name: variant.displayName,
                stats: stats,
                signalCount: variant.intersections?.signalCount,
                stopSignCount: variant.intersections?.stopSignCount
            ))
        }
        // Fastest median wins the ranking; more drives break a tie, then
        // the id, so the list never reorders itself between redraws.
        routes.sort { left, right in
            if left.stats.median != right.stats.median { return left.stats.median < right.stats.median }
            if left.stats.count != right.stats.count { return left.stats.count > right.stats.count }
            return left.id.uuidString < right.id.uuidString
        }

        guard routes.count >= 2 else {
            return Race(routes: routes, outcome: .oneRouteOnly)
        }
        let fastest = routes[0]
        let runnerUp = routes[1]
        let shortfall = max(
            config.minSamplesPerRoute - fastest.stats.count,
            config.minSamplesPerRoute - runnerUp.stats.count
        )
        guard shortfall <= 0 else {
            return Race(routes: routes, outcome: .collecting(drivesNeeded: shortfall))
        }
        let gap = runnerUp.stats.median - fastest.stats.median
        guard gap > config.tieMarginSeconds else {
            return Race(routes: routes, outcome: .tie(gapSeconds: gap))
        }
        let confidence: VerdictEngine.Confidence =
            min(fastest.stats.count, runnerUp.stats.count) >= config.highConfidenceSamples ? .high : .medium
        return Race(routes: routes, outcome: .winner(gapSeconds: gap, confidence: confidence))
    }
}
