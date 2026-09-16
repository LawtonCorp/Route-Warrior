import XCTest

@testable import RouteWarrior

/// D-067: the verdict names the road, and says when the pick and the
/// drive disagree rather than choosing one.
final class VerdictTextTests: XCTestCase {
    private let maple = UUID()
    private let backWay = UUID()

    private func name(_ id: UUID) -> String? {
        [maple: "via Maple Ave", backWay: "the back way"][id]
    }

    func testNoRouteSaysNothing() {
        XCTAssertNil(VerdictText.road(picked: nil, driven: nil, name: name))
    }

    func testADriveMatchedToARouteNamesIt() {
        XCTAssertEqual(VerdictText.road(picked: nil, driven: maple, name: name), "Your route: via Maple Ave")
    }

    func testAPickThatMatchedTheDriveSaysSo() {
        XCTAssertEqual(
            VerdictText.road(picked: maple, driven: maple, name: name), "Your route: via Maple Ave, as picked"
        )
    }

    /// The matcher's answer and the pick are both kept (D-066); the line
    /// shows both rather than trusting either.
    func testAPickThatDisagreesWithTheDriveShowsBoth() {
        XCTAssertEqual(
            VerdictText.road(picked: backWay, driven: maple, name: name), "Picked the back way, drove via Maple Ave"
        )
    }

    func testAPickTheMatcherCouldNotPlaceIsStillReported() {
        XCTAssertEqual(
            VerdictText.road(picked: maple, driven: nil, name: name),
            "Picked via Maple Ave; this drive matched none of your routes"
        )
    }

    /// A deleted route reads as no route on that side, never as a crash.
    func testAVariantThatIsGoneReadsAsNoRoute() {
        let gone = UUID()
        XCTAssertNil(VerdictText.road(picked: nil, driven: gone, name: name))
        XCTAssertEqual(VerdictText.road(picked: gone, driven: maple, name: name), "Your route: via Maple Ave")
    }
}
