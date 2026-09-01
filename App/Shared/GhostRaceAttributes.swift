import ActivityKit
import Foundation

/// The ghost-race Live Activity contract, compiled into both the app (which
/// starts/updates the activity) and the widget extension (which renders it).
/// Listed in project.yml under BOTH targets — a one-sided change breaks the
/// other side at runtime, not compile time.
struct GhostRaceAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Positive = ahead of the reference.
        var aheadSeconds: Double
        /// 0...1 along the recognized route.
        var progress: Double
        /// "personal best" / "your average".
        var referenceLabel: String
    }

    var destinationName: String
    var routeName: String
}
