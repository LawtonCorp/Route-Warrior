import Foundation
import RouteWarriorKit

/// The scoreboard in words. The drive banner reads it today; the car
/// screen will read the same thing, so the phone and the dashboard can
/// never disagree about who is winning (D-035).
enum ScoreboardText {
    struct Row: Equatable {
        let label: String
        let value: String
    }

    /// Gaps under this are a dead heat. Below it the number churns
    /// between ahead and behind every few seconds, which is noise at a
    /// glance and worse at speed.
    static let levelMarginSeconds: Double = 5

    /// "1:32 ahead", "0:45 behind", or "level".
    static func standing(_ seconds: Double) -> String {
        guard abs(seconds) >= levelMarginSeconds else { return "level" }
        return "\(Format.duration(abs(seconds))) \(seconds > 0 ? "ahead" : "behind")"
    }

    /// The one line worth reading at a glance.
    static func headline(_ board: DriveScoreboard, provider: String) -> String {
        guard let ahead = board.aheadOfPlanSeconds else { return "Recording — no plan to race" }
        guard abs(ahead) >= levelMarginSeconds else { return "Level with \(provider)" }
        return "\(Format.duration(abs(ahead))) \(ahead > 0 ? "ahead of" : "behind") \(provider)"
    }

    /// The rows a car screen shows. Ordered by what matters at a glance:
    /// the verdict first, the clock after it.
    static func rows(_ board: DriveScoreboard, provider: String) -> [Row] {
        var rows: [Row] = []
        if let ahead = board.aheadOfPlanSeconds {
            rows.append(Row(label: "vs \(provider)", value: standing(ahead)))
            rows.append(Row(label: "Progress", value: "\(Int((board.progress * 100).rounded()))%"))
        }
        rows.append(Row(label: "Elapsed", value: Format.duration(board.elapsed)))
        if let ghost = board.aheadOfGhostSeconds {
            rows.append(Row(label: "vs your own", value: standing(ghost)))
        }
        rows.append(Row(label: "Route", value: board.offPlan ? "Off the plan" : "On the plan"))
        return rows
    }
}
