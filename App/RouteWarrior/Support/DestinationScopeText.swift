import Foundation

/// What the Destination screen says about the starting point it is
/// answering for (D-076), in one place so the picker's footer, the routes
/// footer and the reason a race is missing cannot drift apart.
enum DestinationScopeText {
    /// Why the head-to-head and the "fastest right now" line are absent
    /// while every starting point is shown at once.
    static let noRaceAcrossOrigins =
        "These routes start in different places, so they are not raced against each other. "
            + "Pick one starting point above to see which way is faster."

    /// Under the picker: what this screen is counting, and what it is
    /// leaving out.
    static func footer(
        scope: DestinationScope.Selection,
        destination: String,
        unscopedDrives: Int
    ) -> String {
        switch scope {
        case .all:
            return "Every drive that ended at \(destination), from anywhere. "
                + "Totals and the heatmap cover them all; routes are not compared across starting points."
        case .origin:
            var text = "Routes, medians and the heatmap cover drives to \(destination) from here only — "
                + "a drive from one place and a drive from another are different journeys."
            if unscopedDrives > 0 {
                text += " \(unscopedDrives) other drive\(unscopedDrives == 1 ? "" : "s") here started elsewhere; "
                    + "see \(DestinationScope.allLabel.lowercased())."
            }
            return text
        }
    }

    /// Under the route list.
    static func routesFooter(scope: DestinationScope.Selection, destination: String) -> String {
        let shared = "Each route is coloured to match its line on the map. Tap one to name it and see its drives."
        switch scope {
        case .all:
            return shared + " Every route here ends at \(destination), but they do not all start in the "
                + "same place — each says where it began."
        case .origin:
            return shared
        }
    }
}
