import Foundation
import UserNotifications

/// What a tap on one of the app's notifications means (D-082).
///
/// Pulled out of the delegate because the delegate is where this went
/// wrong: the destination handler ended in `if let placeID =
/// UUID(uuidString: action)`, and tapping the notification itself sends
/// `UNNotificationDefaultActionIdentifier`, which is not a UUID. The tap
/// fell off the end of the `if` and did nothing at all — no picker, no
/// log line, no way to tell it from a tap that worked.
///
/// Every case is named here, so a response can no longer be dropped by
/// omission, and CI can check the routing that the phone used to have to.
enum PromptResponse: Equatable {
    /// A place button on the departure notification.
    case pick(UUID)
    /// The departure notification itself, tapped: the driver wants to
    /// answer, they just did not find the buttons.
    case openPicker
    case stillHere
    case endDrive
    /// Swiped away, or something this build does not know about.
    case ignore

    static func route(category: String, action: String) -> PromptResponse {
        if action == UNNotificationDismissActionIdentifier { return .ignore }
        switch category {
        case PromptService.pauseCategoryID:
            switch action {
            case PromptService.stillHereAction: return .stillHere
            case PromptService.endDriveAction: return .endDrive
            // Tapping the pause question opens the app, where the same
            // question is waiting as an alert (D-072). Nothing to do.
            default: return .ignore
            }
        case PromptService.destinationCategoryID:
            if let placeID = UUID(uuidString: action) { return .pick(placeID) }
            return action == UNNotificationDefaultActionIdentifier ? .openPicker : .ignore
        default:
            return .ignore
        }
    }
}
