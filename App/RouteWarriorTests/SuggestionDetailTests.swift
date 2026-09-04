import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// Apple's completer answers a chain as its bare name, several times over,
/// with no address (D-040). These pin how the looked-up places take the
/// bare rows' seats so the driver can tell one branch from another.
final class SuggestionDetailTests: XCTestCase {
    private let bare = AddressSuggestion(title: "Extra Space Storage", subtitle: "")
    private let addressed = AddressSuggestion(title: "Extra Innings", subtitle: "12 Bat Ln, Boulder")

    private func branch(_ street: String, at latitude: Double, metres: Double?) -> AddressSuggestion {
        AddressSuggestion(
            title: "Extra Space Storage", subtitle: street,
            coordinate: Coordinate(latitude: latitude, longitude: -105), distanceMeters: metres
        )
    }

    func testABareNameNeedsDetailAndAnAddressedRowDoesNot() {
        XCTAssertTrue(SuggestionDetail.needsDetail(bare))
        XCTAssertTrue(SuggestionDetail.needsDetail(AddressSuggestion(title: "Extra", subtitle: "Search Nearby")))
        XCTAssertFalse(SuggestionDetail.needsDetail(addressed))
        XCTAssertFalse(SuggestionDetail.needsDetail(branch("1 A St", at: 40, metres: nil)))
    }

    func testIdenticalBareRowsCollapseToOneWhileTheLookupIsOut() {
        let rows = SuggestionDetail.merge(completions: [bare, bare, addressed, bare], details: [:])
        XCTAssertEqual(rows, [bare, addressed])
        XCTAssertEqual(SuggestionDetail.namesNeedingDetail(in: [bare, bare, addressed]), ["Extra Space Storage"])
    }

    func testFoundPlacesTakeTheBareRowsSeatInOrder() {
        let near = branch("100 Near Rd", at: 40.01, metres: 800)
        let far = branch("900 Far Ave", at: 40.2, metres: 22_000)
        let rows = SuggestionDetail.merge(
            completions: [addressed, bare, bare],
            details: ["Extra Space Storage": [near, far]]
        )
        XCTAssertEqual(rows, [addressed, near, far])
        // Two branches of one chain are two rows, so the list can key them.
        XCTAssertNotEqual(near.id, far.id)
    }

    func testAnEmptyLookupLeavesTheBareRowSoTheDriverCanStillTapIt() {
        let rows = SuggestionDetail.merge(completions: [bare], details: ["Extra Space Storage": []])
        XCTAssertEqual(rows, [bare])
    }

    func testTheListIsCapped() {
        let branches = (0..<12).map { branch("\($0) St", at: 40 + Double($0) / 100, metres: Double($0) * 1_000) }
        let rows = SuggestionDetail.merge(
            completions: [bare, addressed], details: ["Extra Space Storage": branches], limit: 4
        )
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.map(\.subtitle), ["0 St", "1 St", "2 St", "3 St"])
    }

    func testNearestComesFirstAndUnknownDistanceLast() {
        let unknown = branch("? St", at: 41, metres: nil)
        let far = branch("Far St", at: 40.5, metres: 9_000)
        let near = branch("Near St", at: 40.01, metres: 300)
        XCTAssertEqual(SuggestionDetail.nearest([unknown, far, near]), [near, far, unknown])
        XCTAssertEqual(SuggestionDetail.nearest([unknown, far, near], limit: 2), [near, far])
    }

    func testTheDetailLineLeadsWithDistanceWhenKnown() {
        let line = SuggestionDetail.detailLine(for: branch("100 Near Rd", at: 40.01, metres: 3_218.69))
        XCTAssertTrue(line.hasSuffix(" · 100 Near Rd"), line)
        XCTAssertTrue(line.hasPrefix("2"), "two miles, not metres: \(line)")
        XCTAssertEqual(SuggestionDetail.detailLine(for: addressed), "12 Bat Ln, Boulder")
        XCTAssertEqual(SuggestionDetail.detailLine(for: bare), "")
    }

    func testATappedRowWithACoordinateNeedsNoLookup() {
        // The wiring in HomeView goes straight to the plan when a row
        // knows where it is; the query is only for rows that do not.
        XCTAssertEqual(bare.query, "Extra Space Storage")
        XCTAssertEqual(addressed.query, "Extra Innings, 12 Bat Ln, Boulder")
        XCTAssertNotNil(branch("1 A St", at: 40, metres: 1).coordinate)
    }
}
