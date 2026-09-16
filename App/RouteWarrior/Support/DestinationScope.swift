import Foundation
import RouteWarriorKit
import RouteWarriorStore

/// Which starting point the Destination screen is answering for (D-076).
///
/// Every route, median and heatmap cell on that screen used to pool every
/// drive that *ended* here, from anywhere. A drive home from the corner
/// shop and a drive home from across town are different journeys, so
/// ranking them against each other produced a fastest route that meant
/// nothing, and a heatmap cell that said an hour when one long drive
/// happened to land in it.
///
/// Scoping is the fix: the screen answers for one starting point at a
/// time. Pure, so which drives belong to a scope is a rule CI can check
/// rather than something only a phone can show.
enum DestinationScope {
    /// A starting point this destination has history from.
    struct Origin: Identifiable, Equatable {
        let id: UUID
        let name: String
        let drives: Int
    }

    enum Selection: Equatable, Hashable {
        /// Every drive that ended here, from anywhere. Honest about
        /// totals; incapable of comparing routes (see `comparesRoutes`).
        case all
        case origin(UUID)

        /// Whether a race between these routes would mean anything.
        /// Routes from different starting points are different journeys,
        /// so the head-to-head and the "fastest right now" line are only
        /// shown once the screen is answering for one of them.
        var comparesRoutes: Bool {
            if case .origin = self { return true }
            return false
        }
    }

    /// The starting points these drives came from, most-driven first,
    /// ties broken by name so the list never reorders under the driver.
    ///
    /// Drives that began somewhere not saved as a Place carry no origin
    /// and belong to no scope; they are counted only under `.all`, and
    /// the screen says so.
    static func origins(for trips: [Trip], places: [PlaceRecord]) -> [Origin] {
        var counts: [UUID: Int] = [:]
        for trip in trips {
            guard let originID = trip.originPlaceID else { continue }
            counts[originID, default: 0] += 1
        }
        let named = counts.compactMap { id, drives -> Origin? in
            guard let name = RouteOrigin.name(of: id, in: places) else { return nil }
            return Origin(id: id, name: name, drives: drives)
        }
        return named.sorted {
            $0.drives != $1.drives ? $0.drives > $1.drives : $0.name < $1.name
        }
    }

    /// What the screen opens on: the starting point the driver drives
    /// from most, because that is the journey they came to look at. With
    /// nothing to choose between, `.all` — a single starting point needs
    /// no scoping, and no starting points has nothing to scope.
    static func defaultSelection(for origins: [Origin]) -> Selection {
        origins.count > 1 ? .origin(origins[0].id) : .all
    }

    /// The control only earns its place when there is a choice to make.
    static func showsPicker(for origins: [Origin]) -> Bool {
        origins.count > 1
    }

    /// A selection the data can still honour. An origin whose place was
    /// deleted, or whose last drive here was, falls back to `.all`
    /// rather than showing an empty screen — the same rule a stored map
    /// provider follows when the build can no longer draw it (D-062).
    static func resolved(_ selection: Selection, in origins: [Origin]) -> Selection {
        guard case let .origin(id) = selection else { return .all }
        return origins.contains { $0.id == id } ? selection : .all
    }

    static func trips(_ trips: [Trip], in selection: Selection) -> [Trip] {
        guard case let .origin(id) = selection else { return trips }
        return trips.filter { $0.originPlaceID == id }
    }

    static func variants(_ variants: [RouteVariant], in selection: Selection) -> [RouteVariant] {
        guard case let .origin(id) = selection else { return variants }
        return variants.filter { $0.originPlaceID == id }
    }

    /// What the picker calls the unscoped view.
    static let allLabel = "All starting points"

    static func label(for selection: Selection, in origins: [Origin]) -> String {
        guard case let .origin(id) = selection,
              let origin = origins.first(where: { $0.id == id })
        else { return allLabel }
        return origin.name
    }
}
