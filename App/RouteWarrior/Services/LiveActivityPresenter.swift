import ActivityKit
import Foundation

/// The real GhostRacePresenting: a lock-screen / Dynamic Island Live
/// Activity, because Google Maps owns the foreground while navigating
/// (D-003). Content updates come from the app process during recording.
@MainActor
final class LiveActivityPresenter: GhostRacePresenting {
    private var activity: Activity<GhostRaceAttributes>?

    func startRace(destinationName: String, routeName: String, referenceLabel: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = GhostRaceAttributes(
            destinationName: destinationName,
            routeName: routeName
        )
        let state = GhostRaceAttributes.ContentState(
            aheadSeconds: 0,
            progress: 0,
            referenceLabel: referenceLabel
        )
        activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil)
        )
    }

    func updateRace(aheadSeconds: Double, progress: Double, referenceLabel: String) {
        guard let activity else { return }
        let state = GhostRaceAttributes.ContentState(
            aheadSeconds: aheadSeconds,
            progress: progress,
            referenceLabel: referenceLabel
        )
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func endRace() {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .after(.now + 60))
        }
    }
}
