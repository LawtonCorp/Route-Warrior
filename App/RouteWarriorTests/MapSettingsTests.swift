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

    /// D-034/D-057: the choice must survive a relaunch, or the driver
    /// re-chooses it every trip.
    func testTheNavigationHandoffPersistsOnceChosen() throws {
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }

        let settings = MapSettings(defaults: defaults, googleAvailable: true, googleMapsInstalled: true)
        settings.setNavigation(.googleMaps)
        XCTAssertEqual(settings.navigation, .googleMaps)
        XCTAssertEqual(
            MapSettings(defaults: defaults, googleAvailable: true, googleMapsInstalled: true).navigation,
            .googleMaps
        )

        settings.setNavigation(.routeRebel)
        XCTAssertEqual(
            MapSettings(defaults: defaults, googleAvailable: true, googleMapsInstalled: true).navigation,
            .routeRebel
        )
    }

    // MARK: The default follows what the phone can do (D-062)

    /// Google Maps starts guiding on the tap and reaches the CarPlay
    /// screen, so it leads when it is there. Without it the link would
    /// open a web page mid-drive, so Go stays in the app instead.
    func testTheDefaultIsGoogleMapsOnlyWhenItsAppIsInstalled() throws {
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }

        XCTAssertEqual(
            MapSettings(defaults: defaults, googleAvailable: true, googleMapsInstalled: true).navigation,
            .googleMaps
        )
        XCTAssertEqual(
            MapSettings(defaults: defaults, googleAvailable: true, googleMapsInstalled: false).navigation,
            .routeRebel
        )
    }

    /// Apple Maps always stops to ask for a route again (D-060), so it
    /// is never what an install starts with.
    func testAppleMapsIsNeverADefault() {
        for installed in [true, false] {
            XCTAssertNotEqual(NavigationHandoff.preferred(googleMapsInstalled: installed), .appleMaps)
        }
    }

    func testGoogleMapsIsOfferedOnlyWhenItCanBeHonoured() {
        XCTAssertEqual(
            NavigationHandoff.available(googleMapsInstalled: true), [.routeRebel, .appleMaps, .googleMaps]
        )
        XCTAssertEqual(NavigationHandoff.available(googleMapsInstalled: false), [.routeRebel, .appleMaps])
        // Whatever the phone can do, staying in the app is always one of them.
        for installed in [true, false] {
            let available = NavigationHandoff.available(googleMapsInstalled: installed)
            XCTAssertTrue(available.contains(.routeRebel))
            XCTAssertTrue(available.contains(NavigationHandoff.preferred(googleMapsInstalled: installed)))
        }
    }

    /// Deleting Google Maps must not leave Go opening a web page: the
    /// stored choice falls back the way an unavailable map provider does.
    func testAStoredGoogleChoiceFallsBackWhenTheAppIsGone() throws {
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }
        defaults.set("googleMaps", forKey: "navigationHandoff")

        XCTAssertEqual(
            MapSettings(defaults: defaults, googleAvailable: true, googleMapsInstalled: true).navigation,
            .googleMaps
        )
        XCTAssertEqual(
            MapSettings(defaults: defaults, googleAvailable: true, googleMapsInstalled: false).navigation,
            .routeRebel,
            "the choice is kept in defaults, but it is not acted on while it cannot work"
        )
    }

    func testChoosingAHandoffThePhoneCannotMakeIsRefused() throws {
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }

        let settings = MapSettings(defaults: defaults, googleAvailable: true, googleMapsInstalled: false)
        settings.setNavigation(.googleMaps)
        XCTAssertEqual(settings.navigation, .routeRebel, "unchanged")
        settings.setNavigation(.appleMaps)
        XCTAssertEqual(settings.navigation, .appleMaps, "an available one still takes")
    }

    /// D-060: the pre-D-057 toggle is no longer read. It was set when the
    /// app had no turn-by-turn of its own, so it cannot mean the driver
    /// wants to leave the app now.
    func testTheOldAppleMapsToggleNoLongerDecides() throws {
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }
        defaults.set(true, forKey: "navigateWithAppleMaps")
        XCTAssertEqual(
            MapSettings(defaults: defaults, googleAvailable: true, googleMapsInstalled: false).navigation,
            .routeRebel
        )
        defaults.set("appleMaps", forKey: "navigationHandoff")
        XCTAssertEqual(
            MapSettings(defaults: defaults, googleAvailable: true).navigation, .appleMaps,
            "a choice made in the picker is still honoured"
        )
    }

    /// The stored value did not change with the name, so an install that
    /// already chose in the picker is not reset by this rename.
    func testTheRouteRebelChoiceStillReadsItsStoredValue() throws {
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }
        defaults.set("off", forKey: "navigationHandoff")
        // With Google Maps installed the default would be Google Maps,
        // so this also proves the stored choice beats the default.
        XCTAssertEqual(
            MapSettings(defaults: defaults, googleAvailable: true, googleMapsInstalled: true).navigation,
            .routeRebel
        )
        XCTAssertEqual(NavigationHandoff.allCases.map(\.label), ["Route Rebel", "Apple Maps", "Google Maps"])
        XCTAssertFalse(NavigationHandoff.routeRebel.leavesTheApp)
        XCTAssertTrue(NavigationHandoff.appleMaps.leavesTheApp)
        XCTAssertTrue(NavigationHandoff.googleMaps.leavesTheApp)
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
