import Foundation

/// Whether a following map is still following (D-059). The drive view's
/// camera chases the car, which means every GPS fix moves it — and a
/// driver who pans or pinches has their gesture undone a second later.
/// A gesture suspends the chase; Recenter resumes it. One object, shared
/// by the screen and whichever surface is drawing, so the button and the
/// camera can never disagree.
@MainActor
@Observable
final class MapFollowState {
    private(set) var isFollowing = true

    /// The driver panned, pinched or rotated: the camera is theirs now.
    func userMovedMap() {
        isFollowing = false
    }

    /// Recenter: back to chasing the car.
    func recenter() {
        isFollowing = true
    }

    /// Only a following camera can stop following, so only it offers the
    /// button; a fit-to-content map (the Plan tab, a trip) is already
    /// the driver's to move.
    func showsRecenter(for camera: MapScene.Camera) -> Bool {
        camera == .followUser && !isFollowing
    }

    /// Whether a surface should move the camera on this update.
    func drivesCamera(for camera: MapScene.Camera) -> Bool {
        camera != .followUser || isFollowing
    }
}
