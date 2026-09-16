import Foundation
import RouteWarriorStore

extension TripRecord {
    /// How long the drive took, with any paused time removed (D-069) —
    /// the same subtraction the kit's `Trip.duration` makes, for the
    /// screens that read the record rather than the trip. Every duration
    /// the app shows for a stored drive comes through here, so a pause
    /// cannot be excluded in one place and counted in another.
    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt) - pausedTime)
    }

    /// Actual door-to-door duration minus Google's traffic-aware ETA at
    /// departure: negative means you beat the plan. Nil when the trip has
    /// no comparison. The trip rows and the detail screen must agree on
    /// this number, so it is computed in exactly one place.
    func etaDeltaSeconds(in snapshots: [SnapshotRecord]) -> Double? {
        guard let snapshotID,
              let snapshot = snapshots.first(where: { $0.id == snapshotID })
        else { return nil }
        return duration - snapshot.trafficDuration
    }
}
