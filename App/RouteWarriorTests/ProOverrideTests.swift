import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// D-017 wiring: the owner-build Pro override must be OFF by default — CI
/// builds this host app with `ROUTEWARRIOR_FORCE_PRO` empty, the same way
/// an App Store archive is built — and must accept only the exact opt-in
/// value that scripts/device-build.sh documents.
final class ProOverrideTests: XCTestCase {
    func testOnlyTheExactOptInValueForcesPro() {
        XCTAssertTrue(StoreService.forcesPro(infoValue: "1"))
        XCTAssertTrue(StoreService.forcesPro(infoValue: " 1 "))
        XCTAssertFalse(StoreService.forcesPro(infoValue: ""))
        XCTAssertFalse(StoreService.forcesPro(infoValue: "0"))
        XCTAssertFalse(StoreService.forcesPro(infoValue: "YES"))
        XCTAssertFalse(StoreService.forcesPro(infoValue: "true"))
        XCTAssertFalse(StoreService.forcesPro(infoValue: nil))
        XCTAssertFalse(StoreService.forcesPro(infoValue: 1))
    }

    @MainActor
    func testUnforcedBuildStartsFree() {
        // The host app's Info.plist carries RouteWarriorForcePro from the
        // build setting, which is empty here — so a fresh StoreService must
        // come up .free. This is the proof that the default path (the one
        // every archive takes) is untouched by the override.
        let host = Bundle.main.object(forInfoDictionaryKey: "RouteWarriorForcePro")
        XCTAssertFalse(StoreService.forcesPro(infoValue: host))
        XCTAssertEqual(StoreService().tier, .free)
    }
}
