import Foundation
import RouteWarriorStore

extension TripRecord {
    /// Actual door-to-door duration minus Google's traffic-aware ETA at
    /// departure: negative means you beat the plan. Nil when the trip has
    /// no comparison. The trip rows and the detail screen must agree on
    /// this number, so it is computed in exactly one place.
    func etaDeltaSeconds(in snapshots: [SnapshotRecord]) -> Double? {
        guard let snapshotID,
              let snapshot = snapshots.first(where: { $0.id == snapshotID })
        else { return nil }
        return endedAt.timeIntervalSince(startedAt) - snapshot.trafficDuration
    }
}
