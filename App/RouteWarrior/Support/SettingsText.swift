import Foundation

/// The Map settings' footers (D-068), lifted out of `SettingsView` so the
/// app target can assert that each section explains its own setting.
///
/// One section used to hold both "Map & routes" and "Navigate with" under
/// a header that said only "Map", with a single footer covering every
/// setting in it. Two rows three lines apart could therefore both read
/// "Google" — the map inside the app, and the app Go hands off to — with
/// nothing on screen to say which was which. Splitting the section puts
/// the distinction in the header, where it is read before the value, and
/// gives the hand-off its own footer instead of a paragraph four
/// settings long.
enum SettingsText {
    /// Header for the settings that act inside the app.
    static let inAppHeader = "In Route Rebel"
    /// Header for the one setting that acts when the driver taps Go.
    static let goHeader = "When you tap Go"

    /// Footer under `inAppHeader`: whose map this is, and what the drive
    /// view does with it.
    static func inAppFooter(
        providerCount: Int,
        rerouteAvailable: Bool,
        guidanceAvailable: Bool
    ) -> String {
        var lines: [String] = []
        lines.append(providerCount == 1
            ? "Apple's map and routes. The Google map arrives in a later update; Google's plan is still compared on every trip when a key is present."
            : "Whose map and routes you see inside Route Rebel. Both providers' plans are compared on every trip whichever you pick.")
        lines.append(rerouteAvailable
            ? "Automatic reroute asks for a fresh plan when you leave the one you started with. The original plan stays the baseline for the verdict."
            : "Automatic reroute is part of Pro.")
        lines.append(guidanceAvailable
            ? "Turn-by-turn shows the next maneuver above the scoreboard and speaks it, through the car's speakers when the phone is connected. It follows the plan you left with, then a reroute if you ask for one; the verdict is always against the plan you left with."
            : "Turn-by-turn on the drive view is part of Pro.")
        return lines.joined(separator: " ")
    }

    /// Footer under `goHeader`: which app drives after Go, and — when
    /// Google Maps is absent from the picker — why (D-062).
    static func goFooter(navigation: NavigationHandoff, googleMapsOffered: Bool) -> String {
        // Bound first: a switch expression is not valid as a call
        // argument, only in an assignment or a return.
        let chosen: String = switch navigation {
        case .appleMaps:
            "Go hands the destination to Apple Maps for turn-by-turn, which is what puts guidance on the CarPlay screen. Apple Maps always opens on its own route preview, so you choose a route there as well as here; Route Rebel keeps recording in the background either way."
        case .googleMaps:
            "Go hands the destination to Google Maps for turn-by-turn, on the CarPlay screen when Google Maps is your car's navigation app. Google Maps starts driving straight away and chooses its own route, usually the one Route Rebel shows; the plan you left with stays the baseline, and Route Rebel keeps recording in the background."
        case .routeRebel:
            "Go stays here: the drive view guides you, speaks the turns and keeps the scoreboard on screen, with no second route to pick. Choose a maps app instead to get guidance on the CarPlay screen, which Route Rebel cannot reach."
        }
        var lines: [String] = [chosen]
        if !googleMapsOffered {
            // Otherwise its absence from the picker reads as a bug.
            lines.append("Google Maps is not on this phone, so it is not offered; install it and Route Rebel will hand off to it.")
        }
        return lines.joined(separator: " ")
    }
}
