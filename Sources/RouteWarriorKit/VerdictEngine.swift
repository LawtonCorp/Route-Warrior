import Foundation

/// Answers acceptance query 5: "should I follow Google, or is my route
/// faster?" (FR-14). Compares the median of the driver's own-route times
/// against the Google side — trips that followed Google's plan, plus
/// Google's traffic ETAs from snapshots — and refuses to call a winner
/// below the sample floor.
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
        case google
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
        /// Median(mine) − median(google), seconds; negative = mine faster.
        /// Zero when there is no verdict.
        public var medianDeltaSeconds: Double
        public var mineSampleCount: Int
        public var googleSampleCount: Int
        public var confidence: Confidence
    }

    /// Raw comparison of two duration samples.
    public static func verdict(
        mine: [TimeInterval],
        google: [TimeInterval],
        config: Config = Config()
    ) -> Verdict {
        guard mine.count >= config.minSamplesPerSide, google.count >= config.minSamplesPerSide,
              let myMedian = median(of: mine), let googleMedian = median(of: google)
        else {
            return Verdict(
                winner: .insufficientData,
                medianDeltaSeconds: 0,
                mineSampleCount: mine.count,
                googleSampleCount: google.count,
                confidence: .low
            )
        }
        let delta = myMedian - googleMedian
        let winner: Winner = abs(delta) <= config.tieMarginSeconds
            ? .tie
            : (delta < 0 ? .mine : .google)
        let confidence: Confidence = min(mine.count, google.count) >= config.highConfidenceSamples
            ? .high
            : .medium
        return Verdict(
            winner: winner,
            medianDeltaSeconds: delta,
            mineSampleCount: mine.count,
            googleSampleCount: google.count,
            confidence: confidence
        )
    }

    /// Assembles the sides from a destination's history: deviating trips
    /// are "mine"; followed-plan trips are Google's actuals, and every
    /// snapshot's traffic ETA is Google's claim for that departure.
    public static func verdict(
        forDestination trips: [Trip],
        snapshotsByID: [UUID: PlanSnapshot],
        config: Config = Config()
    ) -> Verdict {
        let usable = trips.filter { !$0.excludedFromStats }
        let mine = usable.filter { $0.followedPlan == false }.map(\.duration)
        var google = usable.filter { $0.followedPlan == true }.map(\.duration)
        for trip in usable where trip.followedPlan == false {
            if let id = trip.snapshotID, let snapshot = snapshotsByID[id] {
                google.append(snapshot.trafficDuration)
            }
        }
        return verdict(mine: mine, google: google, config: config)
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
