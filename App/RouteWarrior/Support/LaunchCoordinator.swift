import Foundation

/// Carries the launch between the app delegate, which learns why the
/// process started, and the App, which owns the services that must start
/// with it (D-078).
///
/// Order-independent on purpose. Whether SwiftUI builds the `App` before
/// UIKit reports the launch is not documented and has changed between
/// releases; a hook that depends on that order is the kind of wiring that
/// passes every test and does nothing on a phone. Either side may arrive
/// first, and the handler runs exactly once, when both have.
@MainActor
final class LaunchCoordinator {
    static let shared = LaunchCoordinator()

    private var reason: LaunchReason?
    private var handler: ((LaunchReason) -> Void)?
    private var delivered = false

    /// The delegate, saying the process started and why.
    func began(_ reason: LaunchReason) {
        self.reason = reason
        deliver()
    }

    /// The App, saying what to do about it.
    func onLaunch(_ handler: @escaping (LaunchReason) -> Void) {
        self.handler = handler
        deliver()
    }

    private func deliver() {
        guard !delivered, let reason, let handler else { return }
        delivered = true
        handler(reason)
    }
}
