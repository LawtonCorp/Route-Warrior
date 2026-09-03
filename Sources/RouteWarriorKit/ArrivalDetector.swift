import Foundation

/// Notices the driver arriving at the planned destination so recording
/// can stop itself (D-038). Arrival is being *near and slow for a while*:
/// inside the radius and under walking pace for the dwell, so driving
/// past the destination on the way somewhere else — through the radius
/// at road speed — never counts. Leaving the radius resets the clock.
public struct ArrivalDetector: Sendable, Equatable {
    public struct Config: Sendable, Equatable {
        /// How close counts as there. Wide enough for a car park or a
        /// street with the entrance round the corner.
        public var radiusM: Double = 150
        /// How long the driver has to be near and slow before it is an
        /// arrival rather than a red light beside the destination.
        public var dwellSeconds: TimeInterval = 20
        /// Under this is parking, crawling or stopped; over it is passing.
        public var maxSpeedMps: Double = 2.5

        public init() {}
    }

    public enum State: Sendable, Equatable {
        case travelling
        /// Inside the radius and slow, since this moment.
        case settling(since: Date)
        case arrived
    }

    public var config: Config
    public private(set) var state: State = .travelling

    public init(config: Config = Config()) {
        self.config = config
    }

    /// Feed every location sample; the result is the state after it.
    /// Once arrived, it stays arrived until `reset()`.
    @discardableResult
    public mutating func ingest(_ point: TrackPoint, destination: Coordinate) -> State {
        if case .arrived = state { return state }
        let near = Geo.distanceMeters(from: point.coordinate, to: destination) <= config.radiusM
        // A negative speed is CoreLocation's "unknown"; treat it as slow
        // rather than fast, or a GPS hiccup at the kerb would undo a
        // real arrival.
        let slow = point.speedMps < config.maxSpeedMps
        guard near, slow else {
            state = .travelling
            return state
        }
        switch state {
        case .travelling, .arrived:
            state = .settling(since: point.timestamp)
        case let .settling(since):
            if point.timestamp.timeIntervalSince(since) >= config.dwellSeconds {
                state = .arrived
            }
        }
        return state
    }

    public mutating func reset() {
        state = .travelling
    }
}
