import Foundation

/// Where the Terms of Use and Privacy Policy live, and which version of
/// the Terms the driver has accepted (D-051, D-053). The documents are
/// bundled from `docs/` and shown in the app; the same files are served
/// on the web, and Apple requires the web links inside an app that
/// sells subscriptions, so both stay (docs/HANDOFF.md §5).
enum Legal {
    /// The effective date at the top of docs/TERMS_OF_USE.md, as
    /// yyyy-MM-dd. `LegalTests` holds it equal to the bundled file's
    /// date; when the Terms change, the date in the file changes and
    /// this must follow, and every install is asked again once (D-053).
    static let termsVersion = "2026-09-10"

    static let termsURL = URL(string: "https://routerebel.app/terms")!
    static let privacyURL = URL(string: "https://routerebel.app/privacy")!

    /// The AppStorage key holding the accepted Terms version.
    static let acceptedTermsKey = "acceptedTermsVersion"

    /// True until the driver has accepted the current Terms — a fresh
    /// install, or an install that accepted an older version.
    static func needsAcceptance(accepted: String?) -> Bool {
        accepted != termsVersion
    }

    /// The line under onboarding's first Continue button, as markdown so
    /// the two names are links.
    static var acceptanceLine: String {
        "By continuing you agree to the [Terms of Use](\(termsURL.absoluteString)) and the [Privacy Policy](\(privacyURL.absoluteString))."
    }

    /// The two documents, by their file in `docs/` and their web address.
    enum Document: CaseIterable {
        case terms
        case privacy

        var title: String {
            switch self {
            case .terms: "Terms of Use"
            case .privacy: "Privacy Policy"
            }
        }

        var resourceName: String {
            switch self {
            case .terms: "TERMS_OF_USE"
            case .privacy: "PRIVACY_POLICY"
            }
        }

        var url: URL {
            switch self {
            case .terms: termsURL
            case .privacy: privacyURL
            }
        }

        var symbol: String {
            switch self {
            case .terms: "doc.text.fill"
            case .privacy: "hand.raised.fill"
            }
        }
    }

    /// The bundled copy, parsed. Nil only if the resource is missing
    /// from the build — `LegalTests` fails first.
    static func bundled(_ document: Document, bundle: Bundle = .main) -> LegalDocument? {
        guard let url = bundle.url(forResource: document.resourceName, withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return LegalDocument(markdown: markdown)
    }
}

/// What the root shows (D-053): onboarding until it is done, then the
/// Terms-changed screen once per new version, then the app.
enum RootRoute: Equatable {
    case onboarding
    case termsUpdate
    case app

    static func route(onboardingComplete: Bool, acceptedTerms: String?) -> RootRoute {
        guard onboardingComplete else { return .onboarding }
        return Legal.needsAcceptance(accepted: acceptedTerms) ? .termsUpdate : .app
    }
}
