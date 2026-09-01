import Foundation

/// Aggregations behind the analytics screens (SPEC §2.3, FR-12/FR-13).
/// Pure functions over trips; the caller decides the grouping (per variant,
/// per destination). Trips marked excluded-from-stats never count.
public enum StatsEngine {
    public struct DurationStats: Sendable, Equatable {
        public var count: Int
        public var mean: TimeInterval
        public var median: TimeInterval
        public var best: TimeInterval
        public var worst: TimeInterval
    }

    /// (weekday 1...7 Sunday-first, 4-hour bucket 0...5) — the axis of the
    /// day×time heatmap. Bucket 0 is midnight–4am, bucket 5 is 8pm–midnight.
    public struct Cell: Sendable, Hashable {
        public var weekday: Int
        public var bucket: Int

        public init(weekday: Int, bucket: Int) {
            self.weekday = weekday
            self.bucket = bucket
        }
    }

    static func included(_ trips: [Trip]) -> [Trip] {
        trips.filter { !$0.excludedFromStats }
    }

    public static func durationStats(for trips: [Trip]) -> DurationStats? {
        let durations = included(trips).map(\.duration).sorted()
        guard !durations.isEmpty else { return nil }
        let count = durations.count
        let median = count.isMultiple(of: 2)
            ? (durations[count / 2 - 1] + durations[count / 2]) / 2
            : durations[count / 2]
        return DurationStats(
            count: count,
            mean: durations.reduce(0, +) / Double(count),
            median: median,
            best: durations[0],
            worst: durations[count - 1]
        )
    }

    /// The heatmap: stats per (weekday, 4-hour bucket), computed in each
    /// trip's own timezone.
    public static func weekdayBucketMatrix(for trips: [Trip]) -> [Cell: DurationStats] {
        var groups: [Cell: [Trip]] = [:]
        for trip in included(trips) {
            groups[cell(for: trip), default: []].append(trip)
        }
        return groups.compactMapValues { durationStats(for: $0) }
    }

    public static func cell(for trip: Trip) -> Cell {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: trip.timezoneID) ?? .init(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.weekday, .hour], from: trip.startedAt)
        return Cell(weekday: components.weekday ?? 1, bucket: (components.hour ?? 0) / 4)
    }

    /// Month-over-month trend, keyed "2026-09", sorted ascending.
    public static func monthlyTrend(for trips: [Trip]) -> [(month: String, stats: DurationStats)] {
        var groups: [String: [Trip]] = [:]
        for trip in included(trips) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: trip.timezoneID) ?? .init(secondsFromGMT: 0)!
            let components = calendar.dateComponents([.year, .month], from: trip.startedAt)
            let key = String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
            groups[key, default: []].append(trip)
        }
        return groups
            .compactMap { key, value in durationStats(for: value).map { (month: key, stats: $0) } }
            .sorted { $0.month < $1.month }
    }

    /// Free-flow baseline: the 5th-percentile duration (nearest-rank) of a
    /// variant's history — "this road, empty". Needs a few trips to mean
    /// anything; nil below `minSamples`.
    public static func freeFlowBaseline(for trips: [Trip], minSamples: Int = 5) -> TimeInterval? {
        let durations = included(trips).map(\.duration).sorted()
        guard durations.count >= minSamples else { return nil }
        let rank = max(0, Int((0.05 * Double(durations.count)).rounded(.up)) - 1)
        return durations[rank]
    }

    /// Actual traffic score: how much slower than free-flow this trip ran.
    /// 1.0 = empty road. Compare with `PlanSnapshot.trafficFactor` (Google's
    /// assumption) to answer acceptance query 3.
    public static func trafficScore(for trip: Trip, freeFlowBaseline: TimeInterval) -> Double? {
        guard freeFlowBaseline > 0 else { return nil }
        return trip.duration / freeFlowBaseline
    }
}
