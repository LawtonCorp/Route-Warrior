import Foundation
import RouteWarriorKit
import UserNotifications

/// The app's one local-notification surface, and deliberately its one
/// `UNUserNotificationCenterDelegate`. `UNUserNotificationCenter` has a
/// single delegate slot, so a second service setting it would silently
/// steal the first's replies — the destination picks would stop arriving
/// and nothing would say so (D-072).
///
/// Two prompts today: FR-6's destination pick, when a drive starts
/// somewhere the predictor cannot call, and "Still there?", when a drive
/// has sat paused long enough to be worth asking about.
@MainActor
final class PromptService: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let destinationCategoryID = "DESTINATION_PICK"
    nonisolated static let pauseCategoryID = "PAUSE_STILL_THERE"
    nonisolated static let stillHereAction = "PAUSE_STILL_HERE"
    nonisolated static let endDriveAction = "PAUSE_END_DRIVE"
    nonisolated static let destinationRequestID = "destination-pick"
    nonisolated static let pauseRequestID = "pause-still-there"

    private let onPick: @MainActor (UUID) -> Void
    private let onStillHere: @MainActor () -> Void
    private let onEndDrive: @MainActor () -> Void
    /// The places last offered. `setNotificationCategories` replaces the
    /// whole set rather than adding to it, so every registration has to
    /// carry both categories — otherwise posting the pause question
    /// would quietly strip the destination actions off a notification
    /// already on the lock screen.
    private var offeredPlaces: [Place] = []

    init(
        onPick: @escaping @MainActor (UUID) -> Void,
        onStillHere: @escaping @MainActor () -> Void,
        onEndDrive: @escaping @MainActor () -> Void
    ) {
        self.onPick = onPick
        self.onStillHere = onStillHere
        self.onEndDrive = onEndDrive
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func promptDestination(with places: [Place]) {
        let top = Array(places.prefix(4))
        guard !top.isEmpty else { return }
        offeredPlaces = top
        // Detached: UNUserNotificationCenter is not Sendable, so the whole
        // interaction stays in one nonisolated region instead of crossing
        // in and out of the main actor. Only values go with it.
        Task.detached {
            await Self.post(
                title: "Recording your drive",
                body: "Where are you headed? Pick a destination to get the Google comparison.",
                categoryID: Self.destinationCategoryID,
                identifier: Self.destinationRequestID,
                places: top
            )
        }
    }

    func promptStillThere(limitMinutes: Int) {
        let places = offeredPlaces
        let body = PauseText.body(limitMinutes: limitMinutes)
        Task.detached {
            await Self.post(
                title: PauseText.title,
                body: body,
                categoryID: Self.pauseCategoryID,
                identifier: Self.pauseRequestID,
                places: places
            )
        }
    }

    /// The question was answered somewhere else — in the app, or by the
    /// drive stopping itself. Take it off the lock screen.
    func clearStillThere() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.pauseRequestID])
        center.removePendingNotificationRequests(withIdentifiers: [Self.pauseRequestID])
    }

    private nonisolated static func post(
        title: String,
        body: String,
        categoryID: String,
        identifier: String,
        places: [Place]
    ) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }
        center.setNotificationCategories(categories(places: places))

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = categoryID
        try? await center.add(UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        ))
    }

    /// Both categories, always — see `offeredPlaces`.
    private nonisolated static func categories(places: [Place]) -> Set<UNNotificationCategory> {
        [
            UNNotificationCategory(
                identifier: destinationCategoryID,
                actions: places.map { UNNotificationAction(identifier: $0.id.uuidString, title: $0.name) },
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: pauseCategoryID,
                actions: [
                    UNNotificationAction(identifier: stillHereAction, title: PauseText.stillHere),
                    UNNotificationAction(
                        identifier: endDriveAction,
                        title: PauseText.endDrive,
                        options: [.destructive]
                    ),
                ],
                intentIdentifiers: []
            ),
        ]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Strings only: the response itself must not cross into the
        // main-actor task, and neither must the completion handler.
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        completionHandler()
        Task { @MainActor [weak self] in
            guard let self else { return }
            if category == Self.pauseCategoryID {
                switch action {
                case Self.stillHereAction: onStillHere()
                case Self.endDriveAction: onEndDrive()
                default: break   // the notification was tapped, not answered
                }
            } else if let placeID = UUID(uuidString: action) {
                onPick(placeID)
            }
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
