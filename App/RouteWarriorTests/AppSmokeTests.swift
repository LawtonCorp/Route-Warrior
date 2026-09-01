import RouteWarriorKit
import XCTest
@testable import RouteWarrior

/// The app target needs at least one real test, because a green kit suite says
/// nothing about wiring: a reducer can pass every test while nothing in the app
/// ever calls it. Keep at least one assertion here per feature that crosses the
/// kit/app boundary.
final class AppSmokeTests: XCTestCase {
    func testAppLinksTheKit() {
        XCTAssertEqual(Greeting.message(for: "CI"), "Hello, CI.")
    }
}
