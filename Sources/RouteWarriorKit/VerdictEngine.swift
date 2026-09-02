import Foundation

/// Answers acceptance query 5: "should I follow the provider, or is my
/// route faster?" (FR-14, FR-23). Compares the median of the driver's
/// own-route times against the provider's side — trips that followed its
/// plan, plus its traffic ETAs from snapshots — and refuses to call a
/// winner below the sample floor. Since D-022 a destination can carry one
/// verdict per provider (Apple, Google).
public enum VerdictEngine {
    public struct Config: Sendable {
        /// Minimum samples per side before a verdict renders (FR-14).
        public var minSamplesPerSide: Int = 5
        /// Median deltas inside this margin are a tie, not a win.
        public var tieMarginSeconds: Double = 30
        /// Both sides at or above this sample count → high confidence.
        public var highConfidenceSamples: Int = 12

        public init() {}
    }

    public enum Winner: String, Sendable {
        case mine
        /// The provider's plan (Google's or Apple's) was faster.
        case provider
        case tie
        case insufficientData
    }

    public enum Confidence: String, Sendable {
        case low
        case medium
        case high
    }

    public struct Verdict: Sendable, Equatable {
        public var winner: Winner
        /// Median(mine) − median(provider), seconds; negative = mine faster.
        /// Zero when there is no verdict.
        public var medianDeltaSeconds: Double
        public var mineSampleCount: Int
        public var providerSampleCount: Int
        public var confidence: Confidence
    }

    /// Raw comparison of two duration samples.
    public static func verdict(
        mine: [TimeInterval],
        provider: [TimeInterval],
        config: Config = Config()
    ) -> Verdict {
        guard mine.count >= config.minSamplesPerSide, provider.count >= config.minSamplesPerSide,
              let myMedian = median(of: mine), let providerMedian = median(of: provider)
        else {
            return Verdict(
                winner: .insufficientData,
                medianDeltaSeconds: 0,
                mineSampleCount: mine.count,
                providerSampleCount: provider.count,
                confidence: .low
            )
        }
        let delta = myMedian - providerMedian
        let winner: Winner = abs(delta) <= config.tieMarginSeconds
            ? .tie
            : (delta < 0 ? .mine : .provider)
        let confidence: Confidence = min(mine.count, provider.count) >= config.highConfidenceSamples
            ? .high
            : .medium
        return Verdict(
            winner: winner,
            medianDeltaSeconds: delta,
            mineSampleCount: mine.count,
            providerSampleCount: provider.count,
            confidence: confidence
        )
    }

    /// Assembles the sides from a destination's history against each
    /// trip's *primary* plan, whichever provider it came from: deviating
    /// trips are "mine"; followed-plan trips are the provider's actuals,
    /// and every snapshot's traffic ETA is the provider's claim for that
    /// departure.
    public static func verdict(
        forDestination trips: [Trip],
        snapshotsByID: [UUID: PlanSnapshot],
        config: Config = Config()
    ) -> Verdict {
        let usable = trips.filter { !$0.excludedFromStats }
        let mine = usable.filter { $0.followedPlan == false }.map(\.duration)
        var theirs = usable.filter { $0.followedPlan == true }.map(\.duration)
        for trip in usable where trip.followedPlan == false {
            if let id = trip.snapshotID, let snapshot = snapshotsByID[id] {
                theirs.append(snapshot.trafficDuration)
            }
        }
        return verdict(mine: mine, provider: theirs, config: config)
    }

    /// The per-provider verdict (FR-23): each trip contributes through
    /// whichever of its two plans came from `provider`, with that plan's
    /// own followed label. Trips with no plan from the provider are silent.
    public static func verdict(
        forDestination trips: [Trip],
        snapshotsByID: [UUID: PlanSnapshot],
        provider: PlanSnapshot.Provider,
        config: Config = Config()
    ) -> Verdict {
        var mine: [TimeInterval] = []
        var theirs: [TimeInterval] = []
        for trip in trips where !trip.excludedFromStats {
            guard let (snapshot, followed) = plan(of: trip, from: provider, snapshotsByID: snapshotsByID) else {
                continue
            }
            switch followed {
            case .some(true):
                theirs.append(trip.duration)
            case .some(false):
                mine.append(trip.duration)
                theirs.append(snapshot.trafficDuration)
            case .none:
                break
            }
        }
        return verdict(mine: mine, provider: theirs, config: config)
    }

    /// The trip's plan from `provider` (primary or alternate) and its
    /// followed label.
    public static func plan(
        of trip: Trip,
        from provider: PlanSnapshot.Provider,
        snapshotsByID: [UUID: PlanSnapshot]
    ) -> (snapshot: PlanSnapshot, followed: Bool?)? {
        if let id = trip.snapshotID, let snapshot = snapshotsByID[id], snapshot.provider == provider {
            return (snapshot, trip.followedPlan)
        }
        if let id = trip.altSnapshotID, let snapshot = snapshotsByID[id], snapshot.provider == provider {
            return (snapshot, trip.followedAltPlan)
        }
        return nil
    }

    static func median(of values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let count = sorted.count
        return count.isMultiple(of: 2)
            ? (sorted[count / 2 - 1] + sorted[count / 2]) / 2
            : sorted[count / 2]
    }
}
