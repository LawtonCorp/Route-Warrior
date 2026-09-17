import XCTest
@testable import RouteWarrior

/// D-079: the tab is called Route, and the app's own copy points at it by
/// that name. Both read the same source, so they cannot drift.
final class RootTabTests: XCTestCase {
    func testTheFirstTabIsCalledRoute() {
        XCTAssertEqual(RootTab.route.title, "Route")
    }

    func testEveryTabHasANamedAndAnIcon() {
        for tab in RootTab.allCases {
            XCTAssertFalse(tab.title.isEmpty, "\(tab) has no name")
            XCTAssertFalse(tab.symbol.isEmpty, "\(tab) has no icon")
        }
    }

    /// Two tabs with one name is a tab bar nobody can describe.
    func testTheNamesAreDistinct() {
        let names = RootTab.allCases.map(\.title)
        XCTAssertEqual(Set(names).count, names.count)
    }
}
