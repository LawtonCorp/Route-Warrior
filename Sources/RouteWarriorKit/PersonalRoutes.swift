import Foundation

/// The driver's own routes to a destination, as rows the Plan tab can
/// offer beside the providers' plans (FR-25, D-066). Membership is every
/// route with a counted drive; the number on a row is the median at the
/// tier the recommendation answered at when that tier counted the
/// route, and the all-time median otherwise — with the drive count that
/// number rests on, so a thin number is never dressed as a fat one.
public enum PersonalRoutes {
    public struct Row: Sendable, Equatable, Identifiable {
        /// The variant.
        public var id: UUID
        public var name: String
        public var polyline: Polyline
        /// Median duration at `tier`; "usually", never "predicted".
        public var usualDuration: TimeInterval
        /// Drives behind `usualDuration`.
        public var drivesCounted: Int
        /// Which drives the number came from.
        public var tier: RouteRecommender.Tier
        /// On the recommendation's top row only: "usually fastest on
        /// weekday mornings", or "no clear winner on weekday mornings".
        /// Nil elsewhere.
        public var claim: String?

        public init(
            id: UUID, name: String, polyline: Polyline, usualDuration: TimeInterval,
            drivesCounted: Int, tier: RouteRecommender.Tier, claim: String? = nil
        ) {
            self.id = id
            self.name = name
            self.polyline = polyline
            self.usualDuration = usualDuration
            self.drivesCounted = drivesCounted
            self.tier = tier
            self.claim = claim
        }
    }

    /// Rows in the order the driver should read them: the recommendation's
    /// order first (fastest at its tier), then any route it did not count,
    /// in all-time order. Empty when no route has a counted drive.
    public static func rows(
        variants: [RouteVariant],
        trips: [Trip],
        context: RouteRecommender.Context,
        config: RouteRecommender.Config = RouteRecommender.Config()
    ) -> [Row] {
        let allTime = RouteRaceEngine.race(variants: variants, trips: trips)
        guard !allTime.routes.isEmpty else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: variants.map { ($0.id, $0) })
        let recommendation = RouteRecommender.recommend(
            variants: variants, trips: trips, context: context, config: config
        )

        var rows: [Row] = []
        var placed: Set<UUID> = []
        if let recommendation {
            let scope = recommendation.tier.scope(for: recommendation.context)
            let suffix = scope.isEmpty ? "" : " \(scope)"
            let topClaim: String? = switch recommendation.race.outcome {
            case .winner: "usually fastest\(suffix)"
            case .tie: "no clear winner\(suffix)"
            case .collecting, .oneRouteOnly: nil
            }
            for (index, route) in recommendation.race.routes.enumerated() {
                guard let variant = byID[route.id] else { continue }
                rows.append(Row(
                    id: route.id, name: route.name, polyline: variant.representativePolyline,
                    usualDuration: route.stats.median, drivesCounted: route.stats.count,
                    tier: recommendation.tier, claim: index == 0 ? topClaim : nil
                ))
                placed.insert(route.id)
            }
        }
        for route in allTime.routes where !placed.contains(route.id) {
            guard let variant = byID[route.id] else { continue }
            rows.append(Row(
                id: route.id, name: route.name, polyline: variant.representativePolyline,
                usualDuration: route.stats.median, drivesCounted: route.stats.count,
                tier: .all
            ))
        }
        return rows
    }
}
