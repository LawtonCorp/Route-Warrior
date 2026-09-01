import Foundation
import Testing
@testable import RouteWarriorKit

/// History is hand-built around a Chicago-timezone week (Sept 1 2025 is a
/// Monday); expected probabilities are the Laplace arithmetic done by hand:
/// (count + 1) / (cellTotal + distinctDestinations).
struct DestinationPredictorTests {
    private let tz = "America/Chicago"
    private let home = UUID()
    private let school = UUID()
    private let work = UUID()
    private let coffee = UUID()

    private func date(_ day: Int, hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: tz)!
        return calendar.date(from: DateComponents(
            year: 2025, month: 9, day: day, hour: hour, minute: minute
        ))!
    }

    /// A minimal trip whose first leg heads along `bearingLongitudeStep`
    /// (positive = east, negative = west) far enough to yield a bearing.
    private func trip(
        from origin: UUID?, to destination: UUID, at start: Date, longitudeStep: Double = 0.005
    ) -> Trip {
        let points = [
            TrackPoint(coordinate: Coordinate(latitude: 0, longitude: 0), timestamp: start, speedMps: 10, horizontalAccuracyM: 5),
            TrackPoint(coordinate: Coordinate(latitude: 0, longitude: longitudeStep), timestamp: start.addingTimeInterval(60), speedMps: 10, horizontalAccuracyM: 5),
        ]
        return Trip(
            startedAt: start,
            endedAt: start.addingTimeInterval(900),
            timezoneID: tz,
            points: points,
            originPlaceID: origin,
            destinationPlaceID: destination
        )
    }

    @Test func emptyHistoryAdvisesNone() {
        let predictor = DestinationPredictor(trips: [])
        #expect(predictor.predictions(fromOrigin: home, at: date(1, hour: 7, minute: 30), timezoneID: tz).isEmpty)
        #expect(predictor.advice(fromOrigin: home, at: date(1, hour: 7, minute: 30), timezoneID: tz) == .none)
    }

    @Test func dominantPatternAdvisesOneSnapshot() {
        // Six Monday-morning school runs, three Monday-evening work trips.
        var trips: [Trip] = []
        for week in 0..<6 {
            trips.append(trip(from: home, to: school, at: date(1 + week * 7, hour: 7, minute: 30)))
        }
        for week in 0..<3 {
            trips.append(trip(from: home, to: work, at: date(1 + week * 7, hour: 17, minute: 0)))
        }
        let predictor = DestinationPredictor(trips: trips)
        let advice = predictor.advice(fromOrigin: home, at: date(8, hour: 7, minute: 30), timezoneID: tz)
        // Cell: 6 school runs. Distinct destinations ever seen: 2.
        // P(school) = (6+1)/(6+2) = 0.875 ≥ 0.6.
        guard case .snapshotOne(let top) = advice else {
            Issue.record("expected one confident snapshot, got \(advice)")
            return
        }
        #expect(top.destinationPlaceID == school)
        #expect(abs(top.probability - 0.875) < 0.0001)
    }

    @Test func ambiguousSlotAdvisesTwoSnapshots() {
        // Same Monday slot, split 3/3 between school and coffee.
        var trips: [Trip] = []
        for week in 0..<3 {
            trips.append(trip(from: home, to: school, at: date(1 + week * 7, hour: 7, minute: 30)))
            trips.append(trip(from: home, to: coffee, at: date(1 + week * 7, hour: 7, minute: 35)))
        }
        let predictor = DestinationPredictor(trips: trips)
        let advice = predictor.advice(fromOrigin: home, at: date(8, hour: 7, minute: 30), timezoneID: tz)
        // P(top) = (3+1)/(6+2) = 0.5: between the 0.35 and 0.6 thresholds.
        guard case .snapshotTwo(let first, let second) = advice else {
            Issue.record("expected two snapshots, got \(advice)")
            return
        }
        #expect(Set([first.destinationPlaceID, second.destinationPlaceID]) == Set([school, coffee]))
    }

    @Test func sparseWeekdayBacksOffToAnyWeekday() {
        // Four Monday school runs; querying a Wednesday morning still finds
        // them through the backoff ladder.
        var trips: [Trip] = []
        for week in 0..<4 {
            trips.append(trip(from: home, to: school, at: date(1 + week * 7, hour: 7, minute: 30)))
        }
        let predictor = DestinationPredictor(trips: trips)
        let ranked = predictor.predictions(fromOrigin: home, at: date(3, hour: 7, minute: 30), timezoneID: tz)
        #expect(ranked.first?.destinationPlaceID == school)
    }

    @Test func initialBearingDisambiguates() {
        // Same slot: school runs head east, work runs head west.
        var trips: [Trip] = []
        for week in 0..<3 {
            trips.append(trip(from: home, to: school, at: date(1 + week * 7, hour: 8, minute: 0), longitudeStep: 0.005))
            trips.append(trip(from: home, to: work, at: date(1 + week * 7, hour: 8, minute: 5), longitudeStep: -0.005))
        }
        let predictor = DestinationPredictor(trips: trips)
        let query = date(8, hour: 8, minute: 0)

        guard case .snapshotTwo = predictor.advice(fromOrigin: home, at: query, timezoneID: tz) else {
            Issue.record("without a bearing the slot is ambiguous")
            return
        }
        let eastward = predictor.advice(
            fromOrigin: home, at: query, timezoneID: tz, initialBearingDegrees: 90
        )
        // Bearing filter leaves the 3 school runs: (3+1)/(3+2) = 0.8 ≥ 0.6.
        guard case .snapshotOne(let top) = eastward else {
            Issue.record("heading east should single out the school, got \(eastward)")
            return
        }
        #expect(top.destinationPlaceID == school)
        #expect(abs(top.probability - 0.8) < 0.0001)
    }

    @Test func excludedTripsTeachNothing() {
        var excluded = trip(from: home, to: school, at: date(1, hour: 7, minute: 30))
        excluded.excludedFromStats = true
        let predictor = DestinationPredictor(trips: [excluded])
        #expect(predictor.advice(fromOrigin: home, at: date(8, hour: 7, minute: 30), timezoneID: tz) == .none)
    }

    @Test func initialBearingNeedsEnoughTrack() {
        let start = date(1, hour: 7, minute: 30)
        let shortLeg = [
            TrackPoint(coordinate: Coordinate(latitude: 0, longitude: 0), timestamp: start, speedMps: 5, horizontalAccuracyM: 5),
            TrackPoint(coordinate: Coordinate(latitude: 0, longitude: 0.001), timestamp: start.addingTimeInterval(20), speedMps: 5, horizontalAccuracyM: 5),
        ]
        #expect(DestinationPredictor.initialBearing(of: shortLeg, overMeters: 300) == nil)

        let longLeg = [
            TrackPoint(coordinate: Coordinate(latitude: 0, longitude: 0), timestamp: start, speedMps: 10, horizontalAccuracyM: 5),
            TrackPoint(coordinate: Coordinate(latitude: 0, longitude: 0.005), timestamp: start.addingTimeInterval(60), speedMps: 10, horizontalAccuracyM: 5),
        ]
        let bearing = DestinationPredictor.initialBearing(of: longLeg, overMeters: 300)
        #expect(bearing != nil && abs(bearing! - 90) < 0.01)
    }

    @Test func bearingBucketsWrapAroundNorth() {
        #expect(DestinationPredictor.bucket(forBearing: 0, width: 45) == 0)
        #expect(DestinationPredictor.bucket(forBearing: 350, width: 45) == 7)
        #expect(DestinationPredictor.bucket(forBearing: 360, width: 45) == 0)
        #expect(DestinationPredictor.bucket(forBearing: -10, width: 45) == 7)
    }
}
