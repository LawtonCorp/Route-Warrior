import Foundation
import Testing
@testable import RouteWarriorKit

/// Hand-built duration lists with hand-computed means, medians, and
/// percentile ranks; calendar cells anchored to a known week (Sept 1 2025
/// is a Monday, Chicago time).
struct StatsEngineTests {
    private let tz = "America/Chicago"

    private func date(_ day: Int, hour: Int, month: Int = 9) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: tz)!
        return calendar.date(from: DateComponents(year: 2025, month: month, day: day, hour: hour))!
    }

    private func trip(day: Int, hour: Int, duration: TimeInterval, month: Int = 9, excluded: Bool = false) -> Trip {
        let start = date(day, hour: hour, month: month)
        var trip = Trip(startedAt: start, endedAt: start.addingTimeInterval(duration), timezoneID: tz, points: [])
        trip.excludedFromStats = excluded
        return trip
    }

    @Test func durationStatsOddCount() {
        let trips = [600.0, 700, 800, 900, 1000].map { trip(day: 1, hour: 7, duration: $0) }
        let stats = StatsEngine.durationStats(for: trips)
        #expect(stats == .init(count: 5, mean: 800, median: 800, best: 600, worst: 1000))
    }

    @Test func durationStatsEvenCountMediansTheMiddlePair() {
        let trips = [600.0, 700, 800, 900].map { trip(day: 1, hour: 7, duration: $0) }
        let stats = StatsEngine.durationStats(for: trips)
        #expect(stats?.median == 750)
        #expect(stats?.mean == 750)
    }

    @Test func excludedTripsAndEmptyInput() {
        let trips = [
            trip(day: 1, hour: 7, duration: 600),
            trip(day: 1, hour: 7, duration: 6_000, excluded: true),
        ]
        #expect(StatsEngine.durationStats(for: trips)?.count == 1)
        #expect(StatsEngine.durationStats(for: trips)?.worst == 600)
        #expect(StatsEngine.durationStats(for: []) == nil)
    }

    @Test func matrixCellsLandOnWeekdayAndFourHourBucket() {
        let trips = [
            trip(day: 1, hour: 7, duration: 600),  // Monday, bucket 1 (4–8)
            trip(day: 1, hour: 7, duration: 700),
            trip(day: 1, hour: 17, duration: 900), // Monday, bucket 4 (16–20)
            trip(day: 2, hour: 7, duration: 650),  // Tuesday, bucket 1
        ]
        let matrix = StatsEngine.weekdayBucketMatrix(for: trips)
        #expect(matrix.count == 3)
        #expect(matrix[.init(weekday: 2, bucket: 1)]?.count == 2)
        #expect(matrix[.init(weekday: 2, bucket: 1)]?.mean == 650)
        #expect(matrix[.init(weekday: 2, bucket: 4)]?.count == 1)
        #expect(matrix[.init(weekday: 3, bucket: 1)]?.count == 1)
    }

    @Test func monthlyTrendSortsAndGroups() {
        let trips = [
            trip(day: 1, hour: 7, duration: 600, month: 10),
            trip(day: 1, hour: 7, duration: 700, month: 9),
            trip(day: 8, hour: 7, duration: 800, month: 9),
        ]
        let trend = StatsEngine.monthlyTrend(for: trips)
        #expect(trend.map(\.month) == ["2025-09", "2025-10"])
        #expect(trend[0].stats.count == 2)
        #expect(trend[1].stats.count == 1)
    }

    @Test func freeFlowBaselineIsTheFifthPercentileNearestRank() {
        // 20 samples, 600...790 by 10: rank = ceil(1) − 1 = 0 → 600.
        let twenty = (0..<20).map { trip(day: 1, hour: 7, duration: 600 + Double($0) * 10) }
        #expect(StatsEngine.freeFlowBaseline(for: twenty) == 600)

        // 40 samples: rank = ceil(2) − 1 = 1 → 610.
        let forty = (0..<40).map { trip(day: 1, hour: 7, duration: 600 + Double($0) * 10) }
        #expect(StatsEngine.freeFlowBaseline(for: forty) == 610)

        let four = (0..<4).map { trip(day: 1, hour: 7, duration: 600) }
        #expect(StatsEngine.freeFlowBaseline(for: four) == nil)
    }

    @Test func trafficScoreIsDurationOverBaseline() {
        let slow = trip(day: 1, hour: 8, duration: 900)
        #expect(StatsEngine.trafficScore(for: slow, freeFlowBaseline: 600) == 1.5)
        #expect(StatsEngine.trafficScore(for: slow, freeFlowBaseline: 0) == nil)
    }
}
