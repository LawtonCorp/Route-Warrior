import Foundation
import RouteWarriorKit
import RouteWarriorStore
import SwiftData

/// Finds the driver's own routes from where they are to where they said
/// they are going (FR-25, D-066), from the store, and hands them to the
/// kit to rank. The origin is whichever saved Place the driver is
/// standing in; no Place, no history, no rows. Trips are filtered in
/// memory — one driver's history is small, and `TripDeletion` already
/// reads the table the same way.
enum PersonalRouteFinder {
    @MainActor
    static func rows(
        from origin: Coordinate,
        to destinationPlaceID: UUID,
        in context: ModelContext,
        now: Date = .now,
        timezoneID: String = TimeZone.current.identifier
    ) -> [PersonalRoutes.Row] {
        guard let places = try? context.fetch(FetchDescriptor<PlaceRecord>()).map({ $0.place() }),
              let originPlace = RouteMatcher.place(containing: origin, in: places),
              originPlace.id != destinationPlaceID,
              let variantRecords = try? context.fetch(FetchDescriptor<VariantRecord>()),
              let tripRecords = try? context.fetch(FetchDescriptor<TripRecord>())
        else { return [] }

        let variants = variantRecords
            .filter { $0.originPlaceID == originPlace.id && $0.destinationPlaceID == destinationPlaceID }
            .compactMap { try? $0.variant() }
        guard !variants.isEmpty else { return [] }
        let ids = Set(variants.map(\.id))
        let trips = tripRecords
            .filter { record in record.variantID.map { ids.contains($0) } ?? false }
            .compactMap { try? $0.trip() }

        return PersonalRoutes.rows(
            variants: variants,
            trips: trips,
            context: RouteRecommender.Context(now: now, timezoneID: timezoneID)
        )
    }
}
