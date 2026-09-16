import Foundation
import RouteWarriorStore

/// Where one of the driver's routes starts (D-075).
///
/// A route is a way of driving one origin→destination *pair*, but the
/// Destination screen lists every route that ends here, from anywhere.
/// Three drives home from three different places are three routes, and
/// until the row said so the screen offered no way to tell them apart —
/// they were even named alike, because the auto-name counts routes
/// within a pair and the screen does not.
enum RouteOrigin {
    /// The saved place a route starts from, or nil when there is nothing
    /// honest to show: a route whose origin place has since been deleted,
    /// or one recorded before the app knew where it began.
    static func name(of originPlaceID: UUID?, in places: [PlaceRecord]) -> String? {
        guard let originPlaceID,
              let place = places.first(where: { $0.id == originPlaceID }),
              !place.name.isEmpty
        else { return nil }
        return place.name
    }

    /// The row's phrasing. Nil rather than "from somewhere": a row that
    /// cannot say where it started says nothing, the way a route with no
    /// intersection data simply omits the counts.
    static func caption(of originPlaceID: UUID?, in places: [PlaceRecord]) -> String? {
        name(of: originPlaceID, in: places).map { "from \($0)" }
    }
}
