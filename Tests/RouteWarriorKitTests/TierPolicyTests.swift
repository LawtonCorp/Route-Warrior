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
}
