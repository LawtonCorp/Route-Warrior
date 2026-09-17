import Foundation

/// Why this process started (D-078).
///
/// iOS relaunches a location app in the background when a significant
/// location change arrives — that is how a drive gets recorded when the
/// app was not left open. The two launches need different words in the
/// recorder log, because "the app was not running" and "the app was
/// running and heard nothing" are different diagnoses and used to look
/// identical: silence.
enum LaunchReason: String, Equatable {
    /// The driver opened the app.
    case foreground
    /// iOS woke the app for a location event, with no window on screen.
    case locationWake

    /// `UIApplication.LaunchOptionsKey.location` is present exactly when
    /// the launch was a location wake. Taken as a `Bool` so the rule is
    /// testable without a UIKit dictionary.
    static func from(hasLocationKey: Bool) -> LaunchReason {
        hasLocationKey ? .locationWake : .foreground
    }

    /// How the launch reads in the recorder log.
    var logLabel: String {
        switch self {
        case .foreground: "opened"
        case .locationWake: "woken by a location change"
        }
    }
}

/// How often a location update that arrives while nothing is recording is
/// worth a log line (D-078). Every such update writes nothing today, so an
/// hour of silence could mean "no drive detected" or "the app was not
/// running at all" — the question this session could not answer from the
/// log. One line every ten minutes settles it without flooding the forty
/// the log keeps.
enum WakeLog {
    static let window: TimeInterval = 10 * 60

    static func shouldLog(at time: Date, lastLoggedAt: Date?, window: TimeInterval = WakeLog.window) -> Bool {
        guard let lastLoggedAt else { return true }
        return time.timeIntervalSince(lastLoggedAt) >= window
    }
}
