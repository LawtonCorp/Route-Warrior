import RouteWarriorStore
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

    /// D-086: the container the store opens is the one registered in the
    /// Lawton LLC team. A mismatch with the entitlement in project.yml
    /// would not crash; the app would quietly fall back to local-only
    /// storage, and no drive would sync.
    func testTheStoreOpensTheRouteRebelContainer() {
        XCTAssertEqual(RouteWarriorStoreFactory.cloudKitContainerID, "iCloud.com.lawtoncorp.routerebel")
    }
}
