import Foundation
import Testing
@testable import RouteWarriorKit

struct VerdictEngineTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func trip(duration: TimeInterval, followed: Bool?, snapshotID: UUID? = nil, excluded: Bool = false) -> Trip {
        var trip = Trip(
            startedAt: t0,
            endedAt: t0.addingTimeInterval(duration),
            timezoneID: "America/Chicago",
            points: [],
            snapshotID: snapshotID,
            followedPlan: followed
        )
        trip.excludedFromStats = excluded
        return trip
    }

    @Test func myRouteWinsWhenMedianIsLower() {
        let verdict = VerdictEngine.verdict(
            mine: [560, 580, 600, 620, 640],
            google: [700, 710, 720, 730, 740]
        )
        #expect(verdict.winner == .mine)
        #expect(verdict.medianDeltaSeconds == -120)
        #expect(verdict.confidence == .medium)
    }

    @Test func googleWinsAndTwelveSamplesEachIsHighConfidence() {
        let verdict = VerdictEngine.verdict(
            mine: Array(repeating: 800, count: 12),
            google: Array(repeating: 700, count: 12)
        )
        #expect(verdict.winner == .google)
        #expect(verdict.medianDeltaSeconds == 100)
        #expect(verdict.confidence == .high)
    }

    @Test func deltasInsideTheMarginAreATie() {
        let verdict = VerdictEngine.verdict(
            mine: Array(repeating: 700, count: 6),
            google: Array(repeating: 720, count: 6)
        )
        #expect(verdict.winner == .tie)
    }

    @Test func fewSamplesRefuseAVerdict() {
        let verdict = VerdictEngine.verdict(mine: [600, 600, 600, 600], google: [700, 700, 700, 700, 700])
        #expect(verdict.winner == .insufficientData)
        #expect(verdict.mineSampleCount == 4)
        #expect(verdict.googleSampleCount == 5)
        #expect(verdict.confidence == .low)
    }

    @Test func destinationAssemblySplitsSidesAndAddsSnapshotClaims() {
        // 5 deviating trips at 600 s; 3 followed trips at 750 s; two of the
        // deviators carry snapshots claiming Google would have taken 800 s.
        let snapA = PlanSnapshot(requestedAt: t0, polyline: Polyline(coordinates: []), distanceM: 0, staticDuration: 700, trafficDuration: 800)
        let snapB = PlanSnapshot(requestedAt: t0, polyline: Polyline(coordinates: []), distanceM: 0, staticDuration: 700, trafficDuration: 800)
        var trips = (0..<5).map { i in
            trip(duration: 600, followed: false, snapshotID: i == 0 ? snapA.id : (i == 1 ? snapB.id : nil))
        }
        trips += (0..<3).map { _ in trip(duration: 750, followed: true) }
        trips.append(trip(duration: 100, followed: nil))              // unlabeled: neither side
        trips.append(trip(duration: 100, followed: false, excluded: true)) // excluded: ignored

        let verdict = VerdictEngine.verdict(
            forDestination: trips,
            snapshotsByID: [snapA.id: snapA, snapB.id: snapB]
        )
        // mine = five 600s; google = [750, 750, 750, 800, 800], median 750.
        #expect(verdict.mineSampleCount == 5)
        #expect(verdict.googleSampleCount == 5)
        #expect(verdict.winner == .mine)
        #expect(verdict.medianDeltaSeconds == -150)
    }
}
