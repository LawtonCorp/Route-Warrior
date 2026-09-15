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

    func testADriversNameOutranksTheJourneyAndTheDate() {
        // D-060: the name the driver typed wins; nil leaves the date.
        XCTAssertEqual(
            TripRowView.headline(label: "School run", origin: "Home", destination: "School"),
            "School run"
        )
        XCTAssertEqual(
            TripRowView.headline(label: "  Dentist  ", origin: nil, destination: nil),
            "Dentist",
            "a typed name identifies a drive the app could not"
        )
        XCTAssertEqual(
            TripRowView.headline(label: "", origin: "Home", destination: "School"),
            "Home → School",
            "clearing the name restores what the app worked out"
        )
        XCTAssertNil(TripRowView.headline(label: "   ", origin: nil, destination: nil))
        XCTAssertNil(TripRowView.headline(label: nil, origin: nil, destination: nil))
    }
}
