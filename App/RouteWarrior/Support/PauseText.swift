import Foundation

/// The words of "Still there?" (D-072), in one place so the alert and the
/// notification cannot promise different things about the same drive.
enum PauseText {
    static let title = "Still there?"
    static let stillHere = "Still here"
    static let endDrive = "End the drive"

    /// What the question says. The limit is named because it is the
    /// driver's own setting and the answer depends on it, and the
    /// consequence is named because "it stops itself" sounds like losing
    /// the drive when it is the opposite — D-069 keeps everything driven.
    static func body(limitMinutes: Int) -> String {
        "Your drive is paused and nothing is being recorded. "
            + "After \(phrase(limitMinutes)) paused it stops itself and saves, "
            + "ending where you paused."
    }

    /// The Settings row's value, and the footer that explains the pair of
    /// thresholds without naming a number the driver cannot change.
    static func limitValue(_ minutes: Int) -> String { phrase(minutes) }

    static func settingsFooter(limitMinutes: Int) -> String {
        "Pause stops the clock without ending the drive: the paused time is not counted "
            + "in the duration you are judged against. If a pause reaches \(phrase(limitMinutes)), "
            + "the drive stops itself and is saved, ending where you paused — nothing you drove is lost. "
            + "You are asked first, with time left to say you are still there."
    }

    private static func phrase(_ value: Int) -> String {
        value == 1 ? "1 minute" : "\(value) minutes"
    }
}
