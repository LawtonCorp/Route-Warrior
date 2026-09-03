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
    /// Hand the destination to Apple Maps at departure (D-034), which is
    /// what puts turn-by-turn on CarPlay.
    private(set) var navigateWithAppleMaps: Bool
    /// End a planned drive on arrival (D-038). On by default: a trip
    /// that ends at the kerb is what the comparison wants.
    private(set) var stopOnArrival: Bool
    let availableProviders: [MapProvider]

    private let defaults: UserDefaults
    private static let providerKey = "mapProvider"
    private static let autoRerouteKey = "autoReroute"
    private static let appleMapsNavigationKey = "navigateWithAppleMaps"
    private static let stopOnArrivalKey = "stopOnArrival"

    init(defaults: UserDefaults = .standard, googleAvailable: Bool) {
        self.defaults = defaults
        availableProviders = googleAvailable ? [.apple, .google] : [.apple]
        let stored = defaults.string(forKey: MapSettings.providerKey)
            .flatMap(MapProvider.init(rawValue:)) ?? MapProvider.default
        provider = availableProviders.contains(stored) ? stored : MapProvider.default
        autoReroute = defaults.bool(forKey: MapSettings.autoRerouteKey)
        navigateWithAppleMaps = defaults.bool(forKey: MapSettings.appleMapsNavigationKey)
        // Unset reads as true — bool(forKey:) alone would read as false.
        stopOnArrival = defaults.object(forKey: MapSettings.stopOnArrivalKey) == nil
            || defaults.bool(forKey: MapSettings.stopOnArrivalKey)
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

    func setNavigateWithAppleMaps(_ on: Bool) {
        navigateWithAppleMaps = on
        defaults.set(on, forKey: Self.appleMapsNavigationKey)
    }

    func setStopOnArrival(_ on: Bool) {
        stopOnArrival = on
        defaults.set(on, forKey: Self.stopOnArrivalKey)
    }

    /// Google mode needs both a key and the Google map surface.
    static func googleAvailable(hasKey: Bool) -> Bool {
        hasKey && googleSurfaceAvailable
    }
}
