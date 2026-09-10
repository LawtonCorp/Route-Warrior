import XCTest
@testable import RouteWarrior

/// D-051: the Terms are accepted by version, so a change to them asks
/// again, and the links Apple requires are real https URLs.
final class LegalTests: XCTestCase {
    func testAcceptanceIsByVersion() {
        XCTAssertTrue(Legal.needsAcceptance(accepted: nil))
        XCTAssertTrue(Legal.needsAcceptance(accepted: "2026-01-01"))
        XCTAssertFalse(Legal.needsAcceptance(accepted: Legal.termsVersion))
    }

    func testTheLinksAreLiveHTTPSAddresses() {
        for url in [Legal.termsURL, Legal.privacyURL] {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertFalse(url.host?.isEmpty ?? true)
        }
        XCTAssertTrue(Legal.acceptanceLine.contains(Legal.termsURL.absoluteString))
        XCTAssertTrue(Legal.acceptanceLine.contains(Legal.privacyURL.absoluteString))
    }
}
