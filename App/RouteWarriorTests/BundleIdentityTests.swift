import XCTest

@testable import RouteWarrior

/// D-085: the app ships as `com.lawtoncorp.routerebel`, and the Pro
/// products sit under that same id. The store record, the subscriptions
/// and the Google key's iOS-app restriction are all keyed on these
/// strings, and none of them can be changed after the first upload.
final class BundleIdentityTests: XCTestCase {
    func testTheHostAppIsRouteRebel() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.lawtoncorp.routerebel")
    }

    @MainActor
    func testTheProProductsSitUnderTheAppsID() {
        let prefix = "com.lawtoncorp.routerebel.pro."
        XCTAssertEqual(StoreService.monthlyID, prefix + "monthly")
        XCTAssertEqual(StoreService.annualID, prefix + "annual")
    }
}
