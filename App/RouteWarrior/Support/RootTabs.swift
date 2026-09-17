import Foundation

/// The tab bar's names and icons, in one place (D-079).
///
/// The app's own copy points at these tabs by name — "drives that start
/// from the Route screen" — and a name that lives in two files drifts the
/// first time one of them changes. This is D-068's lesson about settings
/// labels and their footers, applied to the tabs.
enum RootTab: String, CaseIterable {
    /// Where a drive is planned and started. Called "Plan" until D-079:
    /// the screen is about the route, and "plan" is what the *providers*
    /// hand over — the app used the same word for two things.
    case route
    case trips
    case places
    case settings

    var title: String {
        switch self {
        case .route: "Route"
        case .trips: "Trips"
        case .places: "Places"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .route: "car.fill"
        case .trips: "map"
        case .places: "mappin.and.ellipse"
        case .settings: "gearshape"
        }
    }
}
