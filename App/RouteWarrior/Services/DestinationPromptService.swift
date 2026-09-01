import Foundation
import RouteWarriorKit
import UserNotifications

/// FR-6's one-tap fallback: when a drive starts and no destination clears
/// the predictor's confidence bar, a local notification offers the saved
/// places as actions — one tap fetches the Google comparison for that
/// destination without opening the app. Purely additive: ignoring the
/// notification just means "no comparison", never a blocked recording.
@MainActor
final class DestinationPromptService: NSObject, UNUserNotificationCenterDelegate {
    static let categoryID = "DESTINATION_PICK"
    private let onPick: @MainActor (UUID) -> Void

    init(onPick: @escaping @MainActor (UUID) -> Void) {
        self.onPick = onPick
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func prompt(with places: [Place]) {
        let top = Array(places.prefix(4))
        guard !top.isEmpty else { return }
        // Detached: UNUserNotificationCenter is not Sendable, so the whole
        // interaction stays in one nonisolated region instead of crossing
        // in and out of the main actor.
        Task.detached {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }

            let actions = top.map {
                UNNotificationAction(identifier: $0.id.uuidString, title: $0.name)
            }
            center.setNotificationCategories([
                UNNotificationCategory(
                    identifier: Self.categoryID,
                    actions: actions,
                    intentIdentifiers: []
                ),
            ])

            let content = UNMutableNotificationContent()
            content.title = "Recording your drive"
            content.body = "Where are you headed? Pick a destination to get the Google comparison."
            content.categoryIdentifier = Self.categoryID
            try? await center.add(UNNotificationRequest(
                identifier: "destination-pick",
                content: content,
                trigger: nil
            ))
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let placeID = UUID(uuidString: response.actionIdentifier)
        // Answer the system immediately; the pick itself is fire-and-forget
        // (the completion handler is not Sendable, so it must not cross
        // into the main-actor task).
        completionHandler()
        guard let placeID else { return }
        Task { @MainActor [weak self] in
            self?.onPick(placeID)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
