import Foundation

/// "You have left the plan" (FR-22, D-022). Pure and timestamp-driven:
/// leaving needs sustained distance from the plan so a wide lane or a GPS
/// wobble never trips it; returning needs to come well back inside, so the
/// state does not flap at the threshold. The plan itself never changes —
/// a reroute is a second line, not a new baseline.
public struct OffPlanDetector: Sendable {
    public struct Config: Sendable {
        /// Farther than this from the plan starts the clock.
        public var offPlanDistanceM: Double = 120
        /// Nearer than this ends an off-plan state (hysteresis).
        public var backOnPlanDistanceM: Double = 60
        /// How long the car must stay beyond `offPlanDistanceM` to be off.
        public var confirmDuration: TimeInterval = 20

        public init() {}
    }

    public enum State: Sendable, Equatable {
        case onPlan
        /// `since` is the first sample that was beyond the distance.
        case offPlan(since: Date)
    }

    public private(set) var state: State = .onPlan
    private let plan: Polyline
    private let config: Config
    private var driftingSince: Date?

    public init(plan: Polyline, config: Config = Config()) {
        self.plan = plan
        self.config = config
    }

    @discardableResult
    public mutating func ingest(position: Coordinate, at time: Date) -> State {
        guard let hit = plan.nearestPoint(to: position) else { return state }
        let distance = hit.distanceMeters
        switch state {
        case .onPlan:
            if distance > config.offPlanDistanceM {
                if let since = driftingSince {
                    if time.timeIntervalSince(since) >= config.confirmDuration {
                        state = .offPlan(since: since)
                        driftingSince = nil
                    }
                } else {
                    driftingSince = time
                }
            } else {
                driftingSince = nil
            }
        case .offPlan:
            if distance <= config.backOnPlanDistanceM {
                state = .onPlan
                driftingSince = nil
            }
        }
        return state
    }
}
