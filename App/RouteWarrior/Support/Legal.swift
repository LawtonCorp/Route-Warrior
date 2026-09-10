import Foundation

/// Where the Terms of Use and Privacy Policy live, and which version of
/// the Terms the driver has accepted (D-051). Apple requires functional
/// links to both inside an app that sells subscriptions, so these URLs
/// must be live before submission (docs/HANDOFF.md §5).
enum Legal {
    /// The effective date at the top of docs/TERMS_OF_USE.md. Bump it when
    /// the Terms change and the app asks for acceptance again.
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
}
