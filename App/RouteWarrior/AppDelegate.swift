import UIKit

/// The launch hook (D-078).
///
/// A `.task` on the root view is not one: when iOS relaunches the app in
/// the background for a location event there is no window, so the view is
/// never built and the task never runs. Everything auto-recording depends
/// on — motion updates above all — was started there, which meant a drive
/// taken after iOS had reclaimed the app recorded nothing and left no
/// trace. `didFinishLaunchingWithOptions` runs for that launch too.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        LaunchCoordinator.shared.began(
            LaunchReason.from(hasLocationKey: launchOptions?[.location] != nil)
        )
        return true
    }
}
