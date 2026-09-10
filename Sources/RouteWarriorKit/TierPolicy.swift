import Foundation

/// Every free-vs-Pro limit in one tested place (FR-16). Recording is never
/// gated — data keeps accruing so upgrading is instantly valuable; the
/// gates are on history depth, analyzed destinations, and the ghost race.
public struct TierPolicy: Sendable {
    public enum Tier: String, Sendable {
        case free
        case pro
    }

    public struct Limits: Sendable {
        /// Free tier sees trips at most this many days back.
        public var historyDays: Int = 30
        /// Free tier gets analytics on this many destinations.
        public var analyzedDestinations: Int = 2

        public init() {}
    }

    public var limits: Limits

    public init(limits: Limits = Limits()) {
        self.limits = limits
    }

    /// Recording is never gated, for any tier.
    public func canRecord(_ tier: Tier) -> Bool { true }

    public func canViewTrip(startedAt: Date, now: Date, tier: Tier) -> Bool {
        switch tier {
        case .pro:
            return true
        case .free:
            return now.timeIntervalSince(startedAt) <= Double(limits.historyDays) * 86_400
        }
    }

    /// Nil means unlimited.
    public func analyzedDestinationLimit(for tier: Tier) -> Int? {
        tier == .pro ? nil : limits.analyzedDestinations
    }

    public func canAnalyzeDestination(atRank rank: Int, tier: Tier) -> Bool {
        guard let limit = analyzedDestinationLimit(for: tier) else { return true }
        return rank < limit
    }

    public func ghostRaceAvailable(for tier: Tier) -> Bool {
        tier == .pro
    }

    /// The live in-app drive view (FR-21). Plan preview stays free.
    public func driveViewAvailable(for tier: Tier) -> Bool {
        tier == .pro
    }

    /// Asking a provider for a fresh plan mid-drive (FR-22).
    public func rerouteAvailable(for tier: Tier) -> Bool {
        tier == .pro
    }

    // MARK: D-050 — free shows this drive against this month; Pro shows
    // every drive from every angle. Nothing is ever discarded.

    /// Google's plan on the scoreboard. Apple's directions are free to
    /// ask for; Google's cost per call, so the free tier compares against
    /// Apple and Pro puts Google on the board too.
    public func googleComparisonAvailable(for tier: Tier) -> Bool {
        tier == .pro
    }

    /// Which providers to ask at departure, out of those the build can
    /// reach: everything for Pro, everything but Google for free.
    public func snapshotProviders(
        for tier: Tier,
        available: [PlanSnapshot.Provider]
    ) -> [PlanSnapshot.Provider] {
        googleComparisonAvailable(for: tier) ? available : available.filter { $0 != .googleRoutes }
    }

    /// A destination's day-by-hour heatmap, monthly trend and route race.
    /// The verdict card stays free.
    public func deepAnalyticsAvailable(for tier: Tier) -> Bool {
        tier == .pro
    }

    /// A trip's stops list, turn counts and the way into its
    /// destination's analytics. The map, the times and "you vs the plan"
    /// stay free.
    public func fullTripDetailAvailable(for tier: Tier) -> Bool {
        tier == .pro
    }

    /// Sorting and filtering the trip list.
    public func tripOrganizerAvailable(for tier: Tier) -> Bool {
        tier == .pro
    }
}
