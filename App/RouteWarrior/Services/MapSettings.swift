import Foundation
import RouteWarriorKit

/// The user's map-and-routes preference (FR-19) and the drive-view
/// options (automatic reroute, D-022 Q6). UserDefaults-backed: a device
/// choice, not trip data, so it stays out of the CloudKit store.
@MainActor
@Observable
final class MapSettings {
    /// The Google map surface shipped in M8 (D-024); Google mode still
    /// needs a key with "Maps SDK for iOS" enabled on it.
    static let googleSurfaceAvailable = true

    private(set) var provider: MapProvider
    private(set) var autoReroute: Bool
    /// Hand the destination to a navigation app at departure (D-034,
    /// D-057): Apple Maps puts turn-by-turn on CarPlay; Google Maps does
    /// the same for drivers who run Google Maps on the car screen.
    private(set) var navigation: NavigationHandoff
    /// End a planned drive on arrival (D-038). On by default: a trip
    /// that ends at the kerb is what the comparison wants.
    private(set) var stopOnArrival: Bool
    /// Turn-by-turn on the drive view (D-052): the maneuver banner, and
    /// the voice. Both on by default; the voice can be silenced alone.
    private(set) var guidance: Bool
    private(set) var guidanceVoice: Bool
    let availableProviders: [MapProvider]
    /// Which hand-offs this phone can make (D-062) — Google Maps only
    /// when its app is installed. Read at launch, so installing Google
    /// Maps takes effect the next time Route Rebel starts.
    let availableHandoffs: [NavigationHandoff]

    private let defaults: UserDefaults
    private static let providerKey = "mapProvider"
    private static let autoRerouteKey = "autoReroute"
    private static let navigationKey = "navigationHandoff"
    private static let stopOnArrivalKey = "stopOnArrival"
    private static let guidanceKey = "guidance"
    private static let guidanceVoiceKey = "guidanceVoice"

    init(defaults: UserDefaults = .standard, googleAvailable: Bool, googleMapsInstalled: Bool = false) {
        self.defaults = defaults
        availableProviders = googleAvailable ? [.apple, .google] : [.apple]
        let stored = defaults.string(forKey: MapSettings.providerKey)
            .flatMap(MapProvider.init(rawValue:)) ?? MapProvider.default
        provider = availableProviders.contains(stored) ? stored : MapProvider.default
        autoReroute = defaults.bool(forKey: MapSettings.autoRerouteKey)
        // The pre-D-057 Apple Maps toggle is no longer read (D-060): it
        // was set when the app had no guidance of its own, so it says
        // nothing about whether the driver wants to leave the app now.
        // A stored choice this phone can no longer honour falls back to
        // the default the same way the map provider does (D-062).
        availableHandoffs = NavigationHandoff.available(googleMapsInstalled: googleMapsInstalled)
        let storedHandoff = defaults.string(forKey: MapSettings.navigationKey)
            .flatMap(NavigationHandoff.init(rawValue:))
        if let storedHandoff, availableHandoffs.contains(storedHandoff) {
            navigation = storedHandoff
        } else {
            navigation = NavigationHandoff.preferred(googleMapsInstalled: googleMapsInstalled)
        }
        // Unset reads as true — bool(forKey:) alone would read as false.
        stopOnArrival = defaults.object(forKey: MapSettings.stopOnArrivalKey) == nil
            || defaults.bool(forKey: MapSettings.stopOnArrivalKey)
        guidance = defaults.object(forKey: MapSettings.guidanceKey) == nil
            || defaults.bool(forKey: MapSettings.guidanceKey)
        guidanceVoice = defaults.object(forKey: MapSettings.guidanceVoiceKey) == nil
            || defaults.bool(forKey: MapSettings.guidanceVoiceKey)
    }

    func select(_ provider: MapProvider) {
        guard availableProviders.contains(provider) else { return }
        self.provider = provider
        defaults.set(provider.rawValue, forKey: Self.providerKey)
    }

    func setAutoReroute(_ on: Bool) {
        autoReroute = on
        defaults.set(on, forKey: Self.autoRerouteKey)
    }

    func setNavigation(_ handoff: NavigationHandoff) {
        guard availableHandoffs.contains(handoff) else { return }
        navigation = handoff
        defaults.set(handoff.rawValue, forKey: Self.navigationKey)
    }

    func setStopOnArrival(_ on: Bool) {
        stopOnArrival = on
        defaults.set(on, forKey: Self.stopOnArrivalKey)
    }

    func setGuidance(_ on: Bool) {
        guidance = on
        defaults.set(on, forKey: Self.guidanceKey)
    }

    func setGuidanceVoice(_ on: Bool) {
        guidanceVoice = on
        defaults.set(on, forKey: Self.guidanceVoiceKey)
    }

    /// Google mode needs both a key and the Google map surface.
    static func googleAvailable(hasKey: Bool) -> Bool {
        hasKey && googleSurfaceAvailable
    }
}
