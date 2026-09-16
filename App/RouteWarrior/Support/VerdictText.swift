import Foundation

/// The road under a trip's verdict (D-067, SPEC_PERSONAL_ROUTES §4.5).
/// "You beat Google's ETA" is the verdict; this says which of your routes
/// did it, so the Trips screen reads as evidence for a choice rather than
/// a list of wins. Two facts can be on a trip: the route the driver
/// picked before departing (`chosenVariantID`) and the route the matcher
/// says they drove (`variantID`). They can disagree, and when they do
/// the line says so instead of picking one.
enum VerdictText {
    /// `name` resolves a variant to what the driver calls it; nil when
    /// the variant is gone, which reads the same as no route.
    static func road(picked: UUID?, driven: UUID?, name: (UUID) -> String?) -> String? {
        let pickedName = picked.flatMap(name)
        let drivenName = driven.flatMap(name)
        switch (pickedName, drivenName) {
        case (nil, nil):
            return nil
        case (nil, let drove?):
            return "Your route: \(drove)"
        case (let pick?, nil):
            return "Picked \(pick); this drive matched none of your routes"
        case (let pick?, let drove?):
            return picked == driven ? "Your route: \(drove), as picked" : "Picked \(pick), drove \(drove)"
        }
    }
}
