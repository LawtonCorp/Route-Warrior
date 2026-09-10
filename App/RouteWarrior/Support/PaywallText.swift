import Foundation

/// The words on the paywall's price rows (D-050). The trial is the
/// headline: "7 days free, then $24.99 per year" is a different offer
/// from "$24.99 per year", and StoreKit only tells us the parts.
enum PaywallText {
    static func priceLine(displayPrice: String, period: String, trialDays: Int?) -> String {
        guard let trialDays, trialDays > 0 else { return "\(displayPrice) per \(period)" }
        return "\(trialDays) days free, then \(displayPrice) per \(period)"
    }

    /// "47 drives older than 30 days" — the locked data, counted.
    static func lockedLines(_ summary: LockedDataSummary, historyDays: Int) -> [String] {
        var lines: [String] = []
        if summary.olderTrips > 0 {
            lines.append("\(summary.olderTrips) drive\(summary.olderTrips == 1 ? "" : "s") older than \(historyDays) days")
        }
        if summary.lockedDestinations > 0 {
            lines.append("\(summary.lockedDestinations) more destination\(summary.lockedDestinations == 1 ? "" : "s") to analyze")
        }
        if summary.stops > 0 {
            lines.append("\(summary.stops) stop\(summary.stops == 1 ? "" : "s"), signal by signal")
        }
        return lines
    }
}
