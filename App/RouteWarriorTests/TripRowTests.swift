import XCTest
@testable import RouteWarrior

/// D-054: a trip row names the journey when its places are known.
final class TripRowTests: XCTestCase {
    func testTheJourneyLineNamesWhatIsKnown() {
        XCTAssertEqual(TripRowView.journey(origin: "Home", destination: "School"), "Home → School")
        XCTAssertEqual(TripRowView.journey(origin: nil, destination: "School"), "→ School")
        XCTAssertEqual(TripRowView.journey(origin: "Home", destination: nil), "Home → …")
        XCTAssertNil(TripRowView.journey(origin: nil, destination: nil), "the date takes the line instead")
        XCTAssertNil(TripRowView.journey(origin: "  ", destination: ""))
    }
}
