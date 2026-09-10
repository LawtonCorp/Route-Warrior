import XCTest
@testable import RouteWarrior

/// D-051/D-053: the Terms are accepted by version, so a change to them
/// asks again; the links Apple requires are real https URLs; the bundled
/// documents are the files in docs/, parsed, with the Terms version
/// held equal to the file's effective date.
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
        XCTAssertEqual(Legal.Document.terms.url, Legal.termsURL)
        XCTAssertEqual(Legal.Document.privacy.url, Legal.privacyURL)
    }

    func testTheRootShowsTheTermsOncePerVersion() {
        XCTAssertEqual(RootRoute.route(onboardingComplete: false, acceptedTerms: nil), .onboarding)
        XCTAssertEqual(RootRoute.route(onboardingComplete: false, acceptedTerms: Legal.termsVersion), .onboarding)
        XCTAssertEqual(RootRoute.route(onboardingComplete: true, acceptedTerms: nil), .termsUpdate,
                       "an install from before the Terms existed is asked once")
        XCTAssertEqual(RootRoute.route(onboardingComplete: true, acceptedTerms: ""), .termsUpdate)
        XCTAssertEqual(RootRoute.route(onboardingComplete: true, acceptedTerms: "2026-01-01"), .termsUpdate)
        XCTAssertEqual(RootRoute.route(onboardingComplete: true, acceptedTerms: Legal.termsVersion), .app)
    }

    // MARK: D-053 — the bundled documents

    func testTheBundledDocumentsAreTheFilesInDocs() throws {
        let terms = try XCTUnwrap(Legal.bundled(.terms), "docs/TERMS_OF_USE.md must be a bundle resource (project.yml)")
        XCTAssertEqual(terms.title, "Route Rebel Terms of Use")
        XCTAssertEqual(
            terms.versionKey, Legal.termsVersion,
            "Legal.termsVersion must equal the effective date at the top of docs/TERMS_OF_USE.md"
        )
        XCTAssertTrue(terms.blocks.contains(.heading(level: 2, text: "1. What the App is, and is not")))
        XCTAssertTrue(terms.blocks.contains(.heading(level: 2, text: "14. Apple")), "the custom-EULA clauses ship")

        let privacy = try XCTUnwrap(Legal.bundled(.privacy), "docs/PRIVACY_POLICY.md must be a bundle resource")
        XCTAssertEqual(privacy.title, "Route Rebel Privacy Policy")
        XCTAssertNotNil(privacy.effectiveDate, "the Privacy Policy carries an effective date line")
        XCTAssertTrue(privacy.blocks.contains(.heading(level: 2, text: "What we collect")))

        // Maintainer notes are HTML comments and never reach the screen.
        for document in [terms, privacy] {
            for case let .paragraph(text) in document.blocks {
                XCTAssertFalse(text.contains("Maintainers"), text)
                XCTAssertFalse(text.contains("legal advice"), text)
                XCTAssertFalse(text.contains("<!--"), text)
            }
            XCTAssertFalse(document.blocks.contains(.heading(level: 1, text: document.title)), "the title is the screen's, not the body's")
        }
    }

    func testMarkdownBlocksReadTheSubsetTheDocumentsUse() {
        let markdown = """
        # Title

        <!-- a note
        across lines -->

        _Effective date: 3 March 2027._

        ## 1. First

        One line
        and its continuation.

        - first bullet
          continued
        - second **bold** bullet

        1. step one
        2. step two
           continued

        Closing paragraph.
        """
        let document = LegalDocument(markdown: markdown)
        XCTAssertEqual(document.title, "Title")
        XCTAssertEqual(document.versionKey, "2027-03-03")
        XCTAssertEqual(document.effectiveDateText, "3 March 2027", "the day the document names, in any time zone")
        XCTAssertEqual(document.blocks, [
            .paragraph("_Effective date: 3 March 2027._"),
            .heading(level: 2, text: "1. First"),
            .paragraph("One line and its continuation."),
            .bullets(["first bullet continued", "second **bold** bullet"]),
            .numbered(["step one", "step two continued"]),
            .paragraph("Closing paragraph."),
        ])
        XCTAssertEqual(LegalMarkdown.stripComments("a <!-- x --> b <!-- unterminated"), "a  b ")
        XCTAssertNil(LegalDocument(markdown: "# T\n\nno date here").effectiveDate)
    }

    func testTheTermsScreenSpeaksToNewAndUpdatedInstallsDifferently() {
        // D-054: an install that never accepted any Terms is not told they changed.
        let fresh = TermsUpdateView.copy(previouslyAccepted: "", effective: "10 September 2026")
        XCTAssertEqual(fresh.title, "Before you drive on")
        XCTAssertFalse(fresh.body.contains("changed"))
        XCTAssertTrue(fresh.body.contains("10 September 2026"))
        let updated = TermsUpdateView.copy(previouslyAccepted: "2026-01-01", effective: "10 September 2026")
        XCTAssertEqual(updated.title, "The Terms of Use have changed")
        XCTAssertTrue(updated.body.contains("take effect 10 September 2026"))
        let undated = TermsUpdateView.copy(previouslyAccepted: nil, effective: nil)
        XCTAssertFalse(undated.body.contains("effective"))
    }
}
