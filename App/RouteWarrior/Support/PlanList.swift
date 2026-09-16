import Foundation
import RouteWarriorKit

/// The Plan tab's route list (D-063, D-066). The provider's routes in the
/// order it returned them — recommendation first, alternates under the
/// numbers the provider gave them — with the driver's own routes listed
/// ahead of them when there are any (FR-25). A tap selects a row; it
/// never reorders the list, because a list that rearranges itself under
/// the finger makes every number on screen unreadable.
enum PlanList {
    /// A row's identity, stable across redraws and picks. Provider rows
    /// are numbered; personal rows are their variant.
    enum RowID: Hashable {
        case route(Int)
        case personal(UUID)
    }

    /// The provider's own recommendation.
    static let recommendedRow = RowID.route(0)

    struct Row: Identifiable, Equatable {
        let id: RowID
        var title: String
        /// The provider's forecast, or the driver's usual.
        var eta: TimeInterval
        var distanceM: Double
        var polyline: Polyline
        /// Under the title on a personal row: the claim and its evidence.
        var caption: String?

        var isPersonal: Bool {
            if case .personal = id { return true }
            return false
        }
    }

    /// The provider's routes: row 0 is its recommendation.
    static func rows(_ snapshot: PlanSnapshot) -> [Row] {
        let recommended = Row(
            id: .route(0),
            title: "\(snapshot.provider.displayName)'s plan",
            eta: snapshot.trafficDuration,
            distanceM: snapshot.distanceM,
            polyline: snapshot.polyline
        )
        let alternates = snapshot.alternates.enumerated().map { index, alternate in
            Row(
                id: .route(index + 1),
                title: "Alternate \(index + 1)",
                eta: alternate.trafficDuration,
                distanceM: alternate.polyline.lengthMeters,
                polyline: alternate.polyline
            )
        }
        return [recommended] + alternates
    }

    /// The driver's own routes, in the order the kit ranked them. The
    /// caption says what the number rests on: "usually fastest on weekday
    /// mornings · 9 drives", or just "7 drives" for a route with no claim.
    static func rows(personal routes: [PersonalRoutes.Row]) -> [Row] {
        routes.map { route in
            let drives = "\(route.drivesCounted) drive\(route.drivesCounted == 1 ? "" : "s")"
            let caption = route.claim.map { "\($0) · \(drives)" } ?? drives
            return Row(
                id: .personal(route.id),
                title: "Your way — \(route.name)",
                eta: route.usualDuration,
                distanceM: route.polyline.lengthMeters,
                polyline: route.polyline,
                caption: caption
            )
        }
    }

    /// The snapshot the drive departs with (D-010, FR-20). A provider pick
    /// is applied here, once, to the snapshot as it came back. A personal
    /// pick leaves it untouched: the provider's plan is still the baseline
    /// the drive is judged against (D-066) — the pick changes what is
    /// driven, not what it is measured against.
    static func departure(_ snapshot: PlanSnapshot, selecting id: RowID) -> PlanSnapshot {
        guard case let .route(row) = id, row != 0, snapshot.alternates.indices.contains(row - 1) else {
            return snapshot
        }
        return snapshot.promotingAlternate(at: row - 1)
    }

    /// A pick that no longer names a row falls back to the recommendation.
    static func clamped(_ id: RowID, to snapshot: PlanSnapshot?, personal: [PersonalRoutes.Row]) -> RowID {
        switch id {
        case let .route(row):
            guard let snapshot, rows(snapshot).indices.contains(row) else { return recommendedRow }
            return id
        case let .personal(variantID):
            return personal.contains { $0.id == variantID } ? id : recommendedRow
        }
    }
}
