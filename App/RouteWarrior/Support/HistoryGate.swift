import Foundation
import RouteWarriorKit
import RouteWarriorStore

/// Applies TierPolicy's history window to a trip list (FR-16). Pulled out
/// of the views so the gate is wiring-testable: recording is never gated,
/// only how far back the free tier can look.
enum HistoryGate {
    static func visible(
        _ records: [TripRecord],
        tier: TierPolicy.Tier,
        policy: TierPolicy = TierPolicy(),
        now: Date = .now
    ) -> (visible: [TripRecord], hiddenCount: Int) {
        let visible = records.filter {
            policy.canViewTrip(startedAt: $0.startedAt, now: now, tier: tier)
        }
        return (visible, records.count - visible.count)
    }
}
