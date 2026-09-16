import Foundation

/// How long a paused drive may sit before the app asks whether the driver
/// is still there, and before it stops itself (D-072).
///
/// Pure arithmetic on elapsed seconds, so the app can drive it from a
/// foreground timer, an arriving location sample or a test's synthetic
/// clock without the rule knowing which — and so the two thresholds can
/// never drift into an order that makes no sense.
public enum PauseWatch {
    public struct Config: Sendable {
        /// The drive stops itself after this long paused. The driver's
        /// setting (Settings → Recording); twenty minutes by default.
        public var limit: TimeInterval
        /// "Still there?" never waits longer than this...
        public var askAfterCap: TimeInterval = 12 * 60
        /// ...nor later than this much of the limit, whichever comes
        /// first. At the default limit the two agree exactly — 60% of
        /// twenty minutes is the twelve Brian asked for — and a shorter
        /// limit scales the question down with it, instead of asking
        /// after the drive has already stopped itself.
        public var askFraction: Double = 0.6

        public static let defaultLimit: TimeInterval = 20 * 60

        public init(limit: TimeInterval = Config.defaultLimit) {
            self.limit = limit
        }

        /// When the question is due.
        public var askAfter: TimeInterval {
            max(0, min(askAfterCap, limit * askFraction))
        }
    }

    public enum State: Sendable, Equatable {
        /// Nothing to do yet.
        case waiting
        /// Ask the driver whether the drive is still going.
        case shouldAsk
        /// Stop the drive and save it. Per D-069 a pause that was never
        /// resumed is trailing time, so the trip ends where the driver
        /// paused — nothing driven is lost by letting this happen.
        case shouldStop
    }

    public static func state(
        pausedFor seconds: TimeInterval,
        config: Config = Config()
    ) -> State {
        if seconds >= config.limit { return .shouldStop }
        if seconds >= config.askAfter { return .shouldAsk }
        return .waiting
    }
}
