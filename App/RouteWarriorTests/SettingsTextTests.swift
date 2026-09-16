import XCTest

@testable import RouteWarrior

/// D-068: two settings could both read "Google", so each now sits in its
/// own section with its own footer. These assert the split held — that
/// the in-app footer never explains the hand-off and the Go footer never
/// explains the map, which is the failure the single footer allowed.
final class SettingsTextTests: XCTestCase {
    private func inApp(providerCount: Int = 2, reroute: Bool = true, guidance: Bool = true) -> String {
        SettingsText.inAppFooter(
            providerCount: providerCount, rerouteAvailable: reroute, guidanceAvailable: guidance
        )
    }

    func testTheInAppFooterExplainsTheMapAndNotTheHandoff() {
        let text = inApp()
        XCTAssertTrue(text.contains("inside Route Rebel"))
        XCTAssertTrue(text.contains("Both providers' plans are compared"))
        // The hand-off has its own section now; explaining it here is
        // what made two "Google" rows indistinguishable.
        XCTAssertFalse(text.contains("Go hands the destination"))
        XCTAssertFalse(text.contains("CarPlay"))
    }

    func testTheInAppFooterSaysWhatIsPaidFor() {
        let free = inApp(reroute: false, guidance: false)
        XCTAssertTrue(free.contains("Automatic reroute is part of Pro."))
        XCTAssertTrue(free.contains("Turn-by-turn on the drive view is part of Pro."))
        let pro = inApp()
        XCTAssertFalse(pro.contains("part of Pro"))
        XCTAssertTrue(pro.contains("the verdict is always against the plan you left with"))
    }

    func testAKeylessBuildSaysWhyGoogleIsMissingFromTheMapPicker() {
        let single = inApp(providerCount: 1)
        XCTAssertTrue(single.contains("Apple's map and routes."))
        XCTAssertTrue(single.contains("still compared on every trip when a key is present"))
    }

    func testTheGoFooterNamesTheChosenHandoffAndNothingElse() {
        let rebel = SettingsText.goFooter(navigation: .routeRebel, googleMapsOffered: true)
        XCTAssertTrue(rebel.contains("Go stays here"))
        XCTAssertFalse(rebel.contains("Whose map and routes"))

        let apple = SettingsText.goFooter(navigation: .appleMaps, googleMapsOffered: true)
        XCTAssertTrue(apple.contains("Apple Maps always opens on its own route preview"))

        let google = SettingsText.goFooter(navigation: .googleMaps, googleMapsOffered: true)
        XCTAssertTrue(google.contains("Google Maps starts driving straight away"))
    }

    /// D-062: an absent Google Maps drops out of the picker, and the
    /// footer has to say so or its absence reads as a bug.
    func testTheGoFooterExplainsAMissingGoogleMaps() {
        let absent = SettingsText.goFooter(navigation: .routeRebel, googleMapsOffered: false)
        XCTAssertTrue(absent.contains("Google Maps is not on this phone"))
        let present = SettingsText.goFooter(navigation: .routeRebel, googleMapsOffered: true)
        XCTAssertFalse(present.contains("not on this phone"))
    }

    func testTheHeadersSayWhereEachSettingActs() {
        XCTAssertEqual(SettingsText.inAppHeader, "In Route Rebel")
        XCTAssertEqual(SettingsText.goHeader, "When you tap Go")
    }
}
