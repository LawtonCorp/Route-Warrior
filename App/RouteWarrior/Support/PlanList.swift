import Foundation
import RouteWarriorKit

/// The Plan tab's route list (D-063). One row per route the provider
/// returned, in the order it returned them: the recommendation first,
/// then its alternates under the numbers the provider gave them. A tap
/// selects a row; it never reorders the list, because a list that
/// rearranges itself under the finger makes every number on screen
/// unreadable — the ETA you were reading is somewhere else by the time
/// you look back at it.
enum PlanList {
    /// The provider's own recommendation, always first.
    static let recommendedRow = 0

    /// One row per route the provider offered.
    struct Row: Identifiable, Equatable {
        /// The row's place in the list, which never changes.
        let id: Int
        var title: String
        var eta: TimeInterval
        var distanceM: Double
        var polyline: Polyline
    }

    static func rows(_ snapshot: PlanSnapshot) -> [Row] {
        let recommended = Row(
            id: recommendedRow,
            title: "\(snapshot.provider.displayName)'s plan",
            eta: snapshot.trafficDuration,
            distanceM: snapshot.distanceM,
            polyline: snapshot.polyline
        )
        let alternates = snapshot.alternates.enumerated().map { index, alternate in
            Row(
                id: index + 1,
                title: "Alternate \(index + 1)",
                eta: alternate.trafficDuration,
                distanceM: alternate.polyline.lengthMeters,
                polyline: alternate.polyline
            )
        }
        return [recommended] + alternates
    }

    /// The snapshot the drive departs with (D-010, FR-20). Selection is
    /// applied here, once, to the snapshot as it came back — never
    /// folded into the stored plans, so picking the same row twice lands
    /// in the same place instead of promoting a promotion.
    static func departure(_ snapshot: PlanSnapshot, selecting row: Int) -> PlanSnapshot {
        guard row != recommendedRow, snapshot.alternates.indices.contains(row - 1) else { return snapshot }
        return snapshot.promotingAlternate(at: row - 1)
    }

    /// A row number means nothing against a different list, so a
    /// selection that no longer exists falls back to the recommendation.
    static func clamped(_ row: Int, to snapshot: PlanSnapshot?) -> Int {
        guard let snapshot, rows(snapshot).indices.contains(row) else { return recommendedRow }
        return row
    }
}
