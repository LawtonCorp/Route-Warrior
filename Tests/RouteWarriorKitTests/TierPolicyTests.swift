import Foundation
import Testing
@testable import RouteWarriorKit

struct TierPolicyTests {
    private let policy = TierPolicy()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func recordingIsNeverGated() {
        #expect(policy.canRecord(.free))
        #expect(policy.canRecord(.pro))
    }

    @Test func freeHistoryStopsAtThirtyDays() {
        let recent = now.addingTimeInterval(-29 * 86_400)
        let old = now.addingTimeInterval(-31 * 86_400)
        #expect(policy.canViewTrip(startedAt: recent, now: now, tier: .free))
        #expect(!policy.canViewTrip(startedAt: old, now: now, tier: .free))
        #expect(policy.canViewTrip(startedAt: old, now: now, tier: .pro))
    }

    @Test func freeAnalyzesTwoDestinations() {
        #expect(policy.analyzedDestinationLimit(for: .free) == 2)
        #expect(policy.analyzedDestinationLimit(for: .pro) == nil)
        #expect(policy.canAnalyzeDestination(atRank: 0, tier: .free))
        #expect(policy.canAnalyzeDestination(atRank: 1, tier: .free))
        #expect(!policy.canAnalyzeDestination(atRank: 2, tier: .free))
        #expect(policy.canAnalyzeDestination(atRank: 99, tier: .pro))
    }

    @Test func ghostRaceIsPro() {
        #expect(!policy.ghostRaceAvailable(for: .free))
        #expect(policy.ghostRaceAvailable(for: .pro))
    }

    // MARK: D-050

    /// The free tier never asks Google: it is the one call that costs.
    @Test func freeAsksAppleOnlyAndProAsksEveryone() {
        let both: [PlanSnapshot.Provider] = [.appleMaps, .googleRoutes]
        #expect(policy.snapshotProviders(for: .free, available: both) == [.appleMaps])
        #expect(policy.snapshotProviders(for: .pro, available: both) == both)
        // A keyless build has no Google to withhold.
        #expect(policy.snapshotProviders(for: .free, available: [.appleMaps]) == [.appleMaps])
        #expect(policy.snapshotProviders(for: .pro, available: []) == [])
        #expect(!policy.googleComparisonAvailable(for: .free))
        #expect(policy.googleComparisonAvailable(for: .pro))
    }

    @Test func theDeepAnalysisSurfacesArePro() {
        #expect(!policy.deepAnalyticsAvailable(for: .free))
        #expect(!policy.fullTripDetailAvailable(for: .free))
        #expect(!policy.tripOrganizerAvailable(for: .free))
        #expect(policy.deepAnalyticsAvailable(for: .pro))
        #expect(policy.fullTripDetailAvailable(for: .pro))
        #expect(policy.tripOrganizerAvailable(for: .pro))
    }

    @Test func guidanceGoesWhereTheDriveViewGoes() {
        // D-052: turn-by-turn lives on the drive view, so it is Pro.
        #expect(!policy.guidanceAvailable(for: .free))
        #expect(policy.guidanceAvailable(for: .pro))
        #expect(policy.guidanceAvailable(for: .free) == policy.driveViewAvailable(for: .free))
    }
}
