import Foundation

/// Which of the driver's own routes to take *now* (SPEC_PERSONAL_ROUTES
/// §4.2, D-065). `RouteRaceEngine` answers "which of my ways is faster"
/// over every drive; this asks the same question of the drives that
/// resemble this moment — same weekday and time of day — and widens only
/// as far as the data forces it, naming how far it had to go. "Fastest on
/// Tuesday mornings" and "fastest overall" are different claims, and a
/// comparison app that blurs them loses the trust it is selling.
public enum RouteRecommender {
    public struct Config: Sendable {
        /// Drives per route before any tier may call it (Brian, D-065): a
        /// flat five, stricter than the all-time race's three, because a
        /// claim narrowed to one weekday and slot rests on less.
        public var minSamplesPerRoute: Int = 5
        /// Passed through to the race unchanged.
        public var tieMarginSeconds: Double = 30
        public var highConfidenceSamples: Int = 8

        public init() {}

        var raceConfig: RouteRaceEngine.Config {
            var config = RouteRaceEngine.Config()
            config.minSamplesPerRoute = minSamplesPerRoute
            config.tieMarginSeconds = tieMarginSeconds
            config.highConfidenceSamples = highConfidenceSamples
            return config
        }
    }

    /// How narrowly the answer was drawn, narrowest first. The order is
    /// the backoff order.
    public enum Tier: Sendable, Equatable, CaseIterable {
        /// This weekday, this 4-hour slot.
        case weekdaySlot
        /// Weekday-or-weekend, this slot.
        case dayClassSlot
        /// This slot, any day.
        case slot
        /// Every drive — the same answer the all-time race gives.
        case all
    }

    /// The moment being asked about, as the cell it falls in.
    public struct Context: Sendable, Equatable {
        /// 1...7, Sunday first — `StatsEngine.Cell`'s convention.
        public var weekday: Int
        /// 0...5, four hours each — `StatsEngine.Cell`'s convention.
        public var bucket: Int

        public init(weekday: Int, bucket: Int) {
            self.weekday = weekday
            self.bucket = bucket
        }

        /// `now` in the driver's time zone, bucketed by the rule trips are.
        public init(now: Date, timezoneID: String) {
            let cell = StatsEngine.cell(at: now, timezoneID: timezoneID)
            self.init(weekday: cell.weekday, bucket: cell.bucket)
        }

        public var isWeekend: Bool { Self.isWeekend(weekday) }

        static func isWeekend(_ weekday: Int) -> Bool { weekday == 1 || weekday == 7 }

        /// Whether a trip's cell counts at a tier for this context.
        func admits(_ cell: StatsEngine.Cell, at tier: Tier) -> Bool {
            switch tier {
            case .weekdaySlot: cell.weekday == weekday && cell.bucket == bucket
            case .dayClassSlot: Self.isWeekend(cell.weekday) == isWeekend && cell.bucket == bucket
            case .slot: cell.bucket == bucket
            case .all: true
            }
        }
    }

    public struct Recommendation: Sendable, Equatable {
        /// The race at the answering tier: routes fastest-first, and the
        /// outcome — a winner, or a tie that was not widened away.
        public var race: RouteRaceEngine.Race
        public var tier: Tier
        /// The moment it answers for, kept with the answer so the wording
        /// can never be paired with a different one.
        public var context: Context
        /// Drives the race counted at that tier, across every route.
        public var drivesCounted: Int

        public init(race: RouteRaceEngine.Race, tier: Tier, context: Context, drivesCounted: Int) {
            self.race = race
            self.tier = tier
            self.context = context
            self.drivesCounted = drivesCounted
        }
    }

    /// Narrowest tier first. A `.winner` or a `.tie` answers — a tie at
    /// "Tuesday mornings" is a real finding, not a reason to look at
    /// Wednesdays. `.collecting` and `.oneRouteOnly` widen. If no tier
    /// decides, the all-drives race is returned so the caller can say
    /// how many more drives it wants; nil only when no route has a
    /// counted drive at all.
    public static func recommend(
        variants: [RouteVariant],
        trips: [Trip],
        context: Context,
        config: Config = Config()
    ) -> Recommendation? {
        var widest: Recommendation?
        for tier in Tier.allCases {
            let subset = trips.filter { context.admits(StatsEngine.cell(for: $0), at: tier) }
            let race = RouteRaceEngine.race(variants: variants, trips: subset, config: config.raceConfig)
            let counted = race.routes.reduce(0) { $0 + $1.stats.count }
            let candidate = Recommendation(race: race, tier: tier, context: context, drivesCounted: counted)
            switch race.outcome {
            case .winner, .tie:
                return candidate
            case .collecting, .oneRouteOnly:
                widest = candidate
            }
        }
        guard let widest, !widest.race.routes.isEmpty else { return nil }
        return widest
    }
}

// MARK: - Words

public extension RouteRecommender.Tier {
    /// The claim's scope, ready to follow "usually fastest": "on Tuesday
    /// mornings", "on weekday mornings", "at this time of day", or
    /// nothing for the all-drives tier — that one is just "usually
    /// fastest".
    func scope(for context: RouteRecommender.Context) -> String {
        let slot = RouteRecommender.slotName(context.bucket)
        switch self {
        case .weekdaySlot: return "on \(RouteRecommender.weekdayName(context.weekday)) \(slot)"
        case .dayClassSlot: return "on \(context.isWeekend ? "weekend" : "weekday") \(slot)"
        case .slot: return "at this time of day"
        case .all: return ""
        }
    }
}

public extension RouteRecommender.Recommendation {
    /// One line for a screen: "via Maple Ave is usually fastest on weekday
    /// mornings" or "No clear winner on Tuesday mornings". Nil while the
    /// race is still collecting or has one route — the all-time card
    /// already says so, and a "for now" line would only repeat it.
    var headline: String? {
        let scope = tier.scope(for: context)
        let suffix = scope.isEmpty ? "" : " \(scope)"
        switch race.outcome {
        case .winner:
            guard let fastest = race.fastest else { return nil }
            return "\(fastest.name) is usually fastest\(suffix)"
        case .tie:
            return "No clear winner\(suffix)"
        case .collecting, .oneRouteOnly:
            return nil
        }
    }
}

extension RouteRecommender {
    /// Plural, to follow a weekday: "Tuesday mornings".
    static func slotName(_ bucket: Int) -> String {
        ["overnight", "early mornings", "mornings", "afternoons", "evenings", "nights"][
            max(0, min(5, bucket))
        ]
    }

    static func weekdayName(_ weekday: Int) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][
            max(0, min(6, weekday - 1))
        ]
    }
}
