import Foundation

/// What leaving the trip screen should do (D-080).
///
/// The screen writes the driver's label on the way out — leaving is as
/// much a commit as tapping Done (D-060). But when it is leaving because
/// the drive is being *deleted*, there is nothing to write to: the record
/// is on its way out of the store, and touching a deleted `@Model` is a
/// trap, not an error you can catch.
///
/// The order is the whole rule. Delete first and the screen is still on
/// screen when its record stops existing, and the next read of it — the
/// navigation title, if nothing else — takes the app down with it. So the
/// screen leaves first and the delete happens on the way out.
enum TripScreenExit: Equatable {
    /// The ordinary exit: save what the driver typed.
    case commitLabel
    /// The screen is closing because the drive is being deleted.
    case delete

    static func onDisappear(deleting: Bool) -> TripScreenExit {
        deleting ? .delete : .commitLabel
    }
}
