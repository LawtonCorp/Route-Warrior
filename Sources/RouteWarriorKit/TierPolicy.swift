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
}
