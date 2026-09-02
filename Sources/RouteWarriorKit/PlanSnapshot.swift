import Foundation

/// What the routing provider planned at the moment of departure. Captured in
/// real time because no provider answers "what would you have said an hour
/// ago" (D-010).
public struct PlanSnapshot: Sendable, Equatable, Codable, Identifiable {
    public enum Provider: String, Sendable, Codable, CaseIterable {
        case googleRoutes
        /// MapKit directions (D-022, M7).
        case appleMaps
    }

    public struct AltRoute: Sendable, Equatable, Codable {
        public var polyline: Polyline
        public var staticDuration: TimeInterval
        public var trafficDuration: TimeInterval

        public init(polyline: Polyline, staticDuration: TimeInterval, trafficDuration: TimeInterval) {
            self.polyline = polyline
            self.staticDuration = staticDuration
            self.trafficDuration = trafficDuration
        }
    }

    public var id: UUID
    public var provider: Provider
    public var requestedAt: Date
    public var destinationPlaceID: UUID?
    /// The provider's recommended route.
    public var polyline: Polyline
    public var distanceM: Double
    /// Duration ignoring live traffic.
    public var staticDuration: TimeInterval
    /// Traffic-aware ETA at the moment of the request.
    public var trafficDuration: TimeInterval
    public var alternates: [AltRoute]

    /// The provider's traffic assumption: traffic-aware over free-flow time.
    /// 1.0 means "no traffic expected"; compare with a trip's actual
    /// traffic score to answer acceptance query 3.
    public var trafficFactor: Double {
        staticDuration > 0 ? trafficDuration / staticDuration : 1
    }

    /// Where the plan ends — the last point of the recommended route.
    public var destination: Coordinate? { polyline.coordinates.last }

    public init(
        id: UUID = UUID(),
        provider: Provider = .googleRoutes,
        requestedAt: Date,
        destinationPlaceID: UUID? = nil,
        polyline: Polyline,
        distanceM: Double,
        staticDuration: TimeInterval,
        trafficDuration: TimeInterval,
        alternates: [AltRoute] = []
    ) {
        self.id = id
        self.provider = provider
        self.requestedAt = requestedAt
        self.destinationPlaceID = destinationPlaceID
        self.polyline = polyline
        self.distanceM = distanceM
        self.staticDuration = staticDuration
        self.trafficDuration = trafficDuration
        self.alternates = alternates
    }
}
