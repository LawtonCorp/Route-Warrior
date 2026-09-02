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
            provider: [700, 710, 720, 730, 740]
        )
        #expect(verdict.winner == .mine)
        #expect(verdict.medianDeltaSeconds == -120)
        #expect(verdict.confidence == .medium)
    }

    @Test func googleWinsAndTwelveSamplesEachIsHighConfidence() {
        let verdict = VerdictEngine.verdict(
            mine: Array(repeating: 800, count: 12),
            provider: Array(repeating: 700, count: 12)
        )
        #expect(verdict.winner == .provider)
        #expect(verdict.medianDeltaSeconds == 100)
        #expect(verdict.confidence == .high)
    }

    @Test func deltasInsideTheMarginAreATie() {
        let verdict = VerdictEngine.verdict(
            mine: Array(repeating: 700, count: 6),
            provider: Array(repeating: 720, count: 6)
        )
        #expect(verdict.winner == .tie)
    }

    @Test func fewSamplesRefuseAVerdict() {
        let verdict = VerdictEngine.verdict(mine: [600, 600, 600, 600], provider: [700, 700, 700, 700, 700])
        #expect(verdict.winner == .insufficientData)
        #expect(verdict.mineSampleCount == 4)
        #expect(verdict.providerSampleCount == 5)
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
        #expect(verdict.providerSampleCount == 5)
        #expect(verdict.winner == .mine)
        #expect(verdict.medianDeltaSeconds == -150)
    }
}

// MARK: - Per-provider verdicts (FR-23, D-022)

struct PerProviderVerdictTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let line = Polyline(coordinates: [
        Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 0.05),
    ])

    private func snapshot(_ provider: PlanSnapshot.Provider, eta: TimeInterval) -> PlanSnapshot {
        PlanSnapshot(provider: provider, requestedAt: t0, polyline: line, distanceM: 5_000, staticDuration: eta, trafficDuration: eta)
    }

    private func trip(duration: TimeInterval, primary: PlanSnapshot?, followed: Bool?, alt: PlanSnapshot?, followedAlt: Bool?) -> Trip {
        Trip(
            startedAt: t0, endedAt: t0.addingTimeInterval(duration), timezoneID: "America/Chicago", points: [],
            snapshotID: primary?.id, followedPlan: followed, altSnapshotID: alt?.id, followedAltPlan: followedAlt
        )
    }

    @Test func eachProviderIsJudgedOnlyByItsOwnPlans() {
        // Apple was the plan the driver saw (primary); Google rode along.
        // My way beat Apple's ETA every time and lost to Google's every time.
        var snapshots: [UUID: PlanSnapshot] = [:]
        var trips: [Trip] = []
        for _ in 0..<5 {
            let apple = snapshot(.appleMaps, eta: 800)
            let google = snapshot(.googleRoutes, eta: 500)
            snapshots[apple.id] = apple
            snapshots[google.id] = google
            trips.append(trip(duration: 600, primary: apple, followed: false, alt: google, followedAlt: false))
        }
        let vsApple = VerdictEngine.verdict(forDestination: trips, snapshotsByID: snapshots, provider: .appleMaps)
        let vsGoogle = VerdictEngine.verdict(forDestination: trips, snapshotsByID: snapshots, provider: .googleRoutes)
        #expect(vsApple.winner == .mine)
        #expect(vsApple.medianDeltaSeconds == -200)
        #expect(vsGoogle.winner == .provider)
        #expect(vsGoogle.medianDeltaSeconds == 100)
    }

    @Test func aProviderWithNoPlansHasNoVerdict() {
        var snapshots: [UUID: PlanSnapshot] = [:]
        var trips: [Trip] = []
        for _ in 0..<6 {
            let google = snapshot(.googleRoutes, eta: 500)
            snapshots[google.id] = google
            trips.append(trip(duration: 600, primary: google, followed: false, alt: nil, followedAlt: nil))
        }
        let vsApple = VerdictEngine.verdict(forDestination: trips, snapshotsByID: snapshots, provider: .appleMaps)
        #expect(vsApple.winner == .insufficientData)
        #expect(vsApple.mineSampleCount == 0)
        #expect(vsApple.providerSampleCount == 0)
    }

    @Test func followedTripsCountAsTheProvidersActualsWhicheverSlotTheyRodeIn() {
        var snapshots: [UUID: PlanSnapshot] = [:]
        var trips: [Trip] = []
        for i in 0..<10 {
            let apple = snapshot(.appleMaps, eta: 700)
            let google = snapshot(.googleRoutes, eta: 700)
            snapshots[apple.id] = apple
            snapshots[google.id] = google
            // Google in the alternate slot; half the trips followed it.
            trips.append(trip(duration: i % 2 == 0 ? 650 : 550, primary: apple, followed: false, alt: google, followedAlt: i % 2 == 0))
        }
        let vsGoogle = VerdictEngine.verdict(forDestination: trips, snapshotsByID: snapshots, provider: .googleRoutes)
        // Mine: five 550 s drives. Google: five 650 s actuals + five 700 s ETAs.
        #expect(vsGoogle.mineSampleCount == 5)
        #expect(vsGoogle.providerSampleCount == 10)
        #expect(vsGoogle.winner == .mine)
    }
}
