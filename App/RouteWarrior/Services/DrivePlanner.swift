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

    var hasDestination: Bool { destination != nil }

    /// A new destination clears the last one's plans immediately, so the
    /// map can never show one place's route under another's name. It does
    /// not start loading: the caller may still be waiting for a location
    /// fix, and a planner stuck in `loading` would never retry.
    func start(_ destination: Destination) {
        self.destination = destination
        plans = []
        failed = false
        loading = false
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
    }

    func clear() {
        destination = nil
        plans = []
        loading = false
        failed = false
    }

    /// The plan drawn on the chosen map surface (D-022 §9.2).
    func plan(on surface: PlanSnapshot.Provider) -> PlanSnapshot? {
        plans.first { $0.provider == surface }
    }

    /// The other providers' plans — compared, listed as numbers, never
    /// drawn on this surface.
    func others(on surface: PlanSnapshot.Provider) -> [PlanSnapshot] {
        plans.filter { $0.provider != surface }
    }

    /// Promote one of the drawn plan's alternates to be the plan.
    func promote(alternate index: Int, on surface: PlanSnapshot.Provider) {
        guard let shown = plan(on: surface) else { return }
        plans = plans.map { $0.id == shown.id ? $0.promotingAlternate(at: index) : $0 }
    }
}
