import Foundation
import RouteWarriorKit

/// How a turn count reads on screen. Lefts come first because they are
/// the turns that cost time in America (D-043); a route with no turns
/// says so rather than showing a row of zeros.
enum TurnText {
    /// "2 left · 3 right", with " · 1 U-turn" appended only when there
    /// is one; "No turns" for a straight run.
    static func summary(_ count: TurnCount) -> String {
        guard count.total > 0 else { return "No turns" }
        var parts = ["\(count.left) left", "\(count.right) right"]
        if count.uTurn > 0 {
            parts.append("\(count.uTurn) U-turn\(count.uTurn == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    /// The one number that matters most, for a caption: "3 lefts".
    static func lefts(_ count: TurnCount) -> String {
        "\(count.left) left\(count.left == 1 ? "" : "s")"
    }
}
