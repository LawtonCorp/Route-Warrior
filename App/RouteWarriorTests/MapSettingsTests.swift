import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// FR-19 wiring: the preference persists, never names a provider the
/// build cannot show, and Google mode waits for the Google map (M8).
@MainActor
final class MapSettingsTests: XCTestCase {
    private func freshDefaults() throws -> (UserDefaults, () -> Void) {
        let name = "MapSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    func testWithoutTheGoogleSurfaceOnlyAppleIsOffered() throws {
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }
        defaults.set("google", forKey: "mapProvider") // a stale choice
        let settings = MapSettings(defaults: defaults, googleAvailable: false)
        XCTAssertEqual(settings.availableProviders, [.apple])
        XCTAssertEqual(settings.provider, .apple)
        settings.select(.google)
        XCTAssertEqual(settings.provider, .apple)
    }

    func testSelectionAndAutoReroutePersist() throws {
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }
        let settings = MapSettings(defaults: defaults, googleAvailable: true)
        XCTAssertEqual(settings.provider, .apple, "Apple is the default (D-022 Q4)")
        settings.select(.google)
        settings.setAutoReroute(true)
        let again = MapSettings(defaults: defaults, googleAvailable: true)
        XCTAssertEqual(again.provider, .google)
        XCTAssertTrue(again.autoReroute)
    }

    func testGoogleModeNeedsAKeyAndTheGoogleMap() {
        XCTAssertFalse(MapSettings.googleAvailable(hasKey: false))
        // Until M8 ships the Google surface, a key alone is not enough.
        XCTAssertEqual(MapSettings.googleAvailable(hasKey: true), MapSettings.googleSurfaceAvailable)
    }

    /// D-034/D-057: off until asked for. The choice must survive a
    /// relaunch, or the driver re-chooses it every trip.
    func testTheNavigationHandoffIsOffUntilChosenAndThenPersists() throws {
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }

        let settings = MapSettings(defaults: defaults, googleAvailable: true)
        XCTAssertEqual(settings.navigation, .off)

        settings.setNavigation(.googleMaps)
        XCTAssertEqual(settings.navigation, .googleMaps)
        XCTAssertEqual(MapSettings(defaults: defaults, googleAvailable: true).navigation, .googleMaps)

        settings.setNavigation(.off)
        XCTAssertEqual(MapSettings(defaults: defaults, googleAvailable: true).navigation, .off)
    }

    /// An install that switched on the old Apple Maps toggle keeps Apple
    /// Maps; one that never did starts off.
    func testTheOldAppleMapsToggleCarriesOver() throws {
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }
        defaults.set(true, forKey: "navigateWithAppleMaps")
        XCTAssertEqual(MapSettings(defaults: defaults, googleAvailable: true).navigation, .appleMaps)
        defaults.set("googleMaps", forKey: "navigationHandoff")
        XCTAssertEqual(MapSettings(defaults: defaults, googleAvailable: true).navigation, .googleMaps, "the new key wins")
    }

    /// D-038: on until switched off — a drive that ends at the kerb is
    /// what the comparison wants — and the switch survives a relaunch.
    func testStopOnArrivalIsOnByDefaultAndOffPersists() throws {
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }

        XCTAssertTrue(MapSettings(defaults: defaults, googleAvailable: true).stopOnArrival)

        let settings = MapSettings(defaults: defaults, googleAvailable: true)
        settings.setStopOnArrival(false)
        XCTAssertFalse(settings.stopOnArrival)
        XCTAssertFalse(MapSettings(defaults: defaults, googleAvailable: true).stopOnArrival)

        settings.setStopOnArrival(true)
        XCTAssertTrue(MapSettings(defaults: defaults, googleAvailable: true).stopOnArrival)
    }

    func testGuidanceAndItsVoiceAreOnUntilSwitchedOff() throws {
        // D-052: unset reads as on, like stop-on-arrival.
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }
        let settings = MapSettings(defaults: defaults, googleAvailable: true)
        XCTAssertTrue(settings.guidance)
        XCTAssertTrue(settings.guidanceVoice)
        settings.setGuidanceVoice(false)
        settings.setGuidance(false)
        let again = MapSettings(defaults: defaults, googleAvailable: true)
        XCTAssertFalse(again.guidance)
        XCTAssertFalse(again.guidanceVoice)
    }
}
