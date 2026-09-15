import Foundation
import RouteWarriorKit

/// The Home screen's planning state: where the driver said they are
/// going, the plans that came back for it, and whether the request is in
/// flight. Holding it here keeps the async call in one place and makes
/// the transitions testable without a screen.
@MainActor
@Observable
final class DrivePlanner {
    struct Destination: Equatable {
        var name: String
        var coordinate: Coordinate
        var placeID: UUID?
    }

    private(set) var destination: Destination?
    private(set) var plans: [PlanSnapshot] = []
    private(set) var loading = false
    private(set) var failed = false
    /// Which row of the shown plan's route list the driver picked
    /// (D-063). Row 0 is the provider's recommendation. Held here
    /// rather than folded into `plans`, so the list on screen keeps its
    /// order and its numbers while the drive still departs with the
    /// route that was picked.
    private(set) var selectedRoute = PlanList.recommendedRow

    var hasDestination: Bool { destination != nil }

    /// What the button under the plans says. "Drive without a plan" only
    /// once the providers have answered with nothing; while they are
    /// still being asked the drive is a planned one whose plan is on its
    /// way (D-044), so the button says Go and stays tappable.
    var goTitle: String {
        plans.isEmpty && !loading ? "Drive without a plan" : "Go"
    }

    /// A new destination clears the last one's plans immediately, so the
    /// map can never show one place's route under another's name. It does
    /// not start loading: the caller may still be waiting for a location
    /// fix, and a planner stuck in `loading` would never retry.
    func start(_ destination: Destination) {
        self.destination = destination
        plans = []
        failed = false
        loading = false
        selectedRoute = PlanList.recommendedRow
    }

    func beginFetch() {
        loading = true
    }

    /// Plans land only if they answer the destination still on screen —
    /// picking a second place before the first one's plans arrive must not
    /// draw the first one's route.
    func finish(with plans: [PlanSnapshot], for destination: Destination) {
        guard loading, self.destination == destination else { return }
        self.plans = plans
        loading = false
        failed = plans.isEmpty
        // A new set of routes is a new list; the old row number would
        // point at something else.
        selectedRoute = PlanList.recommendedRow
    }

    func clear() {
        destination = nil
        plans = []
        selectedRoute = PlanList.recommendedRow
        loading = false
        failed = false
    }

    /// The plan belongs to the drive; when the recording that carried it
    /// ends, the destination and its route leave the screen with it
    /// (D-041). Only the end of a recording counts — the start of one,
    /// and a recorder that was already idle, leave the plan alone.
    nonisolated static func planEnds(recordingWas was: Bool, now: Bool, hasDestination: Bool) -> Bool {
        was && !now && hasDestination
    }

    /// The plan drawn on the chosen map surface (D-022 §9.2).
    func plan(on surface: PlanSnapshot.Provider) -> PlanSnapshot? {
        plans.first { $0.provider == surface }
    }

    /// Pick a route off the list. Out-of-range picks fall back to the
    /// provider's recommendation rather than being stored and acted on.
    func select(route row: Int, on surface: PlanSnapshot.Provider) {
        selectedRoute = PlanList.clamped(row, to: plan(on: surface))
    }

    /// The plans as the drive would depart with them (D-063): the shown
    /// surface's snapshot with the driver's pick promoted, every other
    /// provider's untouched. The stored plans are never rewritten, so
    /// nothing on screen moves when the pick changes.
    func departurePlans(on surface: PlanSnapshot.Provider) -> [PlanSnapshot] {
        guard let shown = plan(on: surface) else { return plans }
        let departure = PlanList.departure(shown, selecting: selectedRoute)
        return plans.map { $0.id == shown.id ? departure : $0 }
    }
}
