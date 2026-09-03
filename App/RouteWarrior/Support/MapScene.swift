import Foundation
import RouteWarriorKit

/// Everything a map screen wants drawn, provider-neutral. Each surface
/// (Apple's `Map`, Google's `GMSMapView`) renders the same scene, and the
/// D-022 §9.2 rule — a provider's plan line appears only on that
/// provider's map — is applied here, once, by `drawablePlans(for:)`.
struct MapScene: Equatable {
    enum Camera: Equatable {
        /// Frame every drawn coordinate (plan preview, trip detail).
        case fitContent
        /// Follow the user with heading (the drive view).
        case followUser
    }

    /// Departure plans (primary and alternate), any provider.
    var plans: [PlanSnapshot] = []
    /// A mid-drive reroute, drawn as a second line, never a baseline.
    var reroute: PlanSnapshot?
    /// The driven track, oldest first.
    var trail: [Coordinate] = []
    /// True while the driver is off the plan: the trail turns win-green.
    var offPlan = false
    var destinationName: String?
    var showsTraffic = true
    var camera: Camera = .fitContent
    /// Where the driver is. A scene with nothing of its own to frame
    /// settles here instead of leaving the surface on the whole-country
    /// view its SDK starts with.
    var userLocation: Coordinate?

    /// The plans this surface may draw: only its own provider's, per D-022.
    func drawablePlans(for provider: PlanSnapshot.Provider) -> [PlanSnapshot] {
        plans.filter { $0.provider == provider }
    }

    /// The reroute this surface may draw, same rule.
    func drawableReroute(for provider: PlanSnapshot.Provider) -> PlanSnapshot? {
        reroute.flatMap { $0.provider == provider ? $0 : nil }
    }

    /// Plans present but not drawable here — the screens list them as
    /// numbers instead.
    func undrawnPlans(for provider: PlanSnapshot.Provider) -> [PlanSnapshot] {
        plans.filter { $0.provider != provider }
    }

    /// Where the primary drawable plan ends, for the destination marker.
    func destination(for provider: PlanSnapshot.Provider) -> Coordinate? {
        drawablePlans(for: provider).first?.destination
    }

    /// What a surface should frame when this provider has nothing drawn:
    /// the driver, when their location is known, and nothing otherwise.
    func fallbackCenter(for provider: PlanSnapshot.Provider) -> Coordinate? {
        allCoordinates(for: provider).isEmpty ? userLocation : nil
    }

    /// Every coordinate a surface would show, for fit-to-content cameras.
    func allCoordinates(for provider: PlanSnapshot.Provider) -> [Coordinate] {
        var all = trail
        for plan in drawablePlans(for: provider) {
            all += plan.polyline.coordinates
            for alternate in plan.alternates { all += alternate.polyline.coordinates }
        }
        if let reroute = drawableReroute(for: provider) { all += reroute.polyline.coordinates }
        return all
    }
}
