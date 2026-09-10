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
        /// The alternate's own maneuvers (D-052), so promoting it keeps
        /// guidance. In memory only: the store drops them.
        public var steps: [PlanStep]

        public init(
            polyline: Polyline,
            staticDuration: TimeInterval,
            trafficDuration: TimeInterval,
            steps: [PlanStep] = []
        ) {
            self.polyline = polyline
            self.staticDuration = staticDuration
            self.trafficDuration = trafficDuration
            self.steps = steps
        }

        private enum CodingKeys: String, CodingKey {
            case polyline, staticDuration, trafficDuration, steps
        }

        /// Alternates persisted before D-052 carry no steps.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            polyline = try container.decode(Polyline.self, forKey: .polyline)
            staticDuration = try container.decode(TimeInterval.self, forKey: .staticDuration)
            trafficDuration = try container.decode(TimeInterval.self, forKey: .trafficDuration)
            steps = try container.decodeIfPresent([PlanStep].self, forKey: .steps) ?? []
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
    /// The maneuvers along the recommended route, for in-app guidance
    /// (D-052). Held for the drive and never persisted: the verdict needs
    /// the line and the times, not the words.
    public var steps: [PlanStep]

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
        alternates: [AltRoute] = [],
        steps: [PlanStep] = []
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
        self.steps = steps
    }

    private enum CodingKeys: String, CodingKey {
        case id, provider, requestedAt, destinationPlaceID, polyline, distanceM
        case staticDuration, trafficDuration, alternates, steps
    }

    /// Snapshots encoded before D-052 carry no steps.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        provider = try container.decode(Provider.self, forKey: .provider)
        requestedAt = try container.decode(Date.self, forKey: .requestedAt)
        destinationPlaceID = try container.decodeIfPresent(UUID.self, forKey: .destinationPlaceID)
        polyline = try container.decode(Polyline.self, forKey: .polyline)
        distanceM = try container.decode(Double.self, forKey: .distanceM)
        staticDuration = try container.decode(TimeInterval.self, forKey: .staticDuration)
        trafficDuration = try container.decode(TimeInterval.self, forKey: .trafficDuration)
        alternates = try container.decodeIfPresent([AltRoute].self, forKey: .alternates) ?? []
        steps = try container.decodeIfPresent([PlanStep].self, forKey: .steps) ?? []
    }
}

public extension PlanSnapshot {
    /// The same departure with the alternate at `index` as the recommended
    /// route and the former recommendation demoted to an alternate (FR-20:
    /// tapping an alternate on the Plan screen makes it the plan). The id
    /// is kept: it is still this departure's snapshot from this provider.
    func promotingAlternate(at index: Int) -> PlanSnapshot {
        guard alternates.indices.contains(index) else { return self }
        var promoted = self
        let chosen = alternates[index]
        var rest = alternates
        rest.remove(at: index)
        rest.insert(
            AltRoute(
                polyline: polyline, staticDuration: staticDuration, trafficDuration: trafficDuration,
                steps: steps
            ),
            at: 0
        )
        promoted.polyline = chosen.polyline
        promoted.staticDuration = chosen.staticDuration
        promoted.trafficDuration = chosen.trafficDuration
        promoted.distanceM = chosen.polyline.lengthMeters
        promoted.alternates = rest
        promoted.steps = chosen.steps
        return promoted
    }
}
