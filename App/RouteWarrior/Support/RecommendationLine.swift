import Foundation
import RouteWarriorKit

/// The "right now" line under a destination's head-to-head card (D-065).
/// Pure, so the one app-side rule — when the line would only repeat the
/// card — is tested without a screen.
enum RecommendationLine {
    /// Nil when there is nothing to add: no recommendation, one that is
    /// still collecting, or one drawn from every drive — the all-time
    /// card above it already says exactly that.
    static func text(for recommendation: RouteRecommender.Recommendation?) -> String? {
        guard let recommendation, recommendation.tier != .all,
              let headline = recommendation.headline
        else { return nil }
        let n = recommendation.drivesCounted
        return "Right now: \(headline) · \(n) drive\(n == 1 ? "" : "s")"
    }
}
