import CoreLocation
import XCTest

@testable import RouteWarrior

/// D-020: the permission walk-through must end on Always, tell the truth
/// about While Using, and never offer a prompt iOS will silently ignore.
final class LocationPrimerTests: XCTestCase {
    func testNothingGrantedAsksWhileUsingFirst() {
        XCTAssertEqual(LocationPrimer.step(for: .notDetermined, alwaysRequested: false), .askWhileUsing)
        XCTAssertEqual(LocationPrimer.step(for: .notDetermined, alwaysRequested: true), .askWhileUsing)
    }

    func testWhileUsingAsksForAlwaysExactlyOnceThenSendsToSettings() {
        // iOS shows the "Change to Always Allow" prompt once per install; a
        // second request is a no-op, so the button must become a Settings link.
        XCTAssertEqual(LocationPrimer.step(for: .authorizedWhenInUse, alwaysRequested: false), .askAlways)
        XCTAssertEqual(LocationPrimer.step(for: .authorizedWhenInUse, alwaysRequested: true), .openSettingsForAlways)
    }

    func testAlwaysIsDoneAndDeniedGoesToSettings() {
        XCTAssertEqual(LocationPrimer.step(for: .authorizedAlways, alwaysRequested: false), .done)
        XCTAssertEqual(LocationPrimer.step(for: .authorizedAlways, alwaysRequested: true), .done)
        XCTAssertEqual(LocationPrimer.step(for: .denied, alwaysRequested: false), .openSettingsForLocation)
        XCTAssertEqual(LocationPrimer.step(for: .restricted, alwaysRequested: true), .openSettingsForLocation)
    }

    func testOnlyAlwaysIsFreeOfAWarning() {
        XCTAssertNil(LocationPrimer.warning(for: .authorizedAlways))
        for status in [CLAuthorizationStatus.notDetermined, .authorizedWhenInUse, .denied, .restricted] {
            let warning = LocationPrimer.warning(for: status)
            XCTAssertNotNil(warning, "\(status.rawValue)")
            XCTAssertTrue(warning?.contains("Always") == true, "every warning names the fix: \(warning ?? "")")
        }
        // While Using must say what it costs, not just that it is not Always.
        XCTAssertTrue(LocationPrimer.warning(for: .authorizedWhenInUse)?.contains("Record button") == true)
    }
}
