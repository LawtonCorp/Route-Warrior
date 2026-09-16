import Foundation
import RouteWarriorKit

/// What the Plan tab shows of the recorder, and when (D-045, D-046).
/// Pure so the rules are testable without a screen.
enum HomeLayout {
    /// Record lives in the navigation bar, and only while there is
    /// nothing else that would start a drive: no destination (Go would),
    /// no drive in progress (Stop is on the recorder row). The recorder
    /// arming itself is not a drive yet, so Record stays for a missed
    /// detection.
    static func showsRecordButton(hasDestination: Bool, state: TripRecorder.State) -> Bool {
        !driveInProgress(state) && !hasDestination
    }

    /// A drive is under way, running or paused (D-069). Paused is a drive
    /// with its clock stopped, so every rule that asks "is one already
    /// running" must answer yes — otherwise pausing puts Record and Go
    /// back on a screen that already has a drive to finish.
    static func driveInProgress(_ state: TripRecorder.State) -> Bool {
        state == .recording || state == .paused
    }

    /// Go is on the screen once there is somewhere to go and the drive
    /// has not already started — Stop belongs to a drive in progress,
    /// and two ways to start one is the mistake D-045 fixed.
    static func showsGoButton(hasDestination: Bool, state: TripRecorder.State) -> Bool {
        hasDestination && !driveInProgress(state)
    }

    /// Where the recorder's one line sits (D-061).
    enum RecorderSlot: Equatable {
        /// Its own card beneath the map, as since D-047: a drive in
        /// progress (the line carries Stop and the drive view), or a
        /// detected drive on a screen with no Go to sit under.
        case ownCard
        /// Beneath the Go button, where the line doubles as the control
        /// that discloses what Go does.
        case underGo
        /// An idle recorder with nothing to explain takes no space.
        /// Named `hidden` rather than `none`, which every call site would
        /// have to disambiguate from `Optional.none`.
        case hidden
    }

    /// `showsGo` is `showsGoButton` for the same state — the two rules
    /// read the same predicate so the line can never claim a place
    /// under a button that is not there.
    static func recorderSlot(state: TripRecorder.State, showsGo: Bool) -> RecorderSlot {
        // Recording keeps its own card: the line carries buttons of its
        // own, and Go is never beside it to be explained.
        if driveInProgress(state) { return .ownCard }
        if showsGo { return .underGo }
        return state == .armed ? .ownCard : .hidden
    }

    /// The words on the recorder row (D-056). Armed says what it means
    /// for the driver — nothing to do — not how the recorder works.
    static func recorderCaption(_ state: TripRecorder.State) -> String {
        switch state {
        case .recording: "Rec"
        case .paused: "Paused — nothing is being recorded"
        default: "Drive detected — recording starts on its own"
        }
    }

    /// The tappable line under Go (D-061). A detected drive says so in
    /// its own words; otherwise the line names what it will reveal, so
    /// the explanation is still reachable on a screen where the
    /// recorder has detected nothing.
    static func goNoteTitle(_ state: TripRecorder.State) -> String {
        state == .armed ? recorderCaption(.armed) : "What happens when you tap Go"
    }
}
