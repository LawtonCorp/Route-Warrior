import CoreLocation
import GoogleMaps
import RouteWarriorKit
import SwiftUI
import UIKit

/// Google's map through the official Maps SDK for iOS (M8, D-024). The
/// SDK draws its own logo and attribution; nothing here covers them.
/// Renders the shared `MapScene` with the same colours as the Apple
/// surface, drawing only Google's plans (D-022 §9.2).
struct GoogleMapSurface: UIViewRepresentable {
    var scene: MapScene

    private static let provider = PlanSnapshot.Provider.googleRoutes

    final class Coordinator {
        var framedForCamera: MapScene.Camera?
        var framedPlanIDs: [UUID] = []
        /// The zoom this surface last set. If the map sits at a different
        /// one, the driver changed it and it is theirs to keep.
        var appliedZoom: Float?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        // Best guess first: this scene's location, then wherever the maps
        // were last looking. The country view is the last resort, for a
        // first launch that has never had a fix.
        if let start = scene.userLocation ?? LastMapCenter.load() {
            options.camera = GMSCameraPosition(
                latitude: start.latitude, longitude: start.longitude, zoom: Self.aroundDriverZoom
            )
        } else {
            options.camera = GMSCameraPosition(latitude: 39.5, longitude: -98.35, zoom: 3)
        }
        let view = GMSMapView(options: options)
        view.isMyLocationEnabled = true
        view.settings.myLocationButton = true
        view.settings.compassButton = true
        return view
    }

    func updateUIView(_ view: GMSMapView, context: Context) {
        view.isTrafficEnabled = scene.showsTraffic
        view.clear()

        for plan in scene.drawablePlans(for: Self.provider) {
            for alternate in plan.alternates {
                let line = GMSPolyline(path: Self.path(alternate.polyline.coordinates))
                line.strokeColor = UIColor.secondaryLabel.withAlphaComponent(0.5)
                line.strokeWidth = 3
                line.zIndex = 1
                line.map = view
            }
            let path = Self.path(plan.polyline.coordinates)
            // A solid ribbon under the dashes. Google's own traffic layer
            // paints every road green, amber and red, and a thin dashed
            // line disappears into it — worst at drive-view zoom, where
            // only a dash or two is on screen at once. The ribbon also
            // means the whole route stays visible even if the dash
            // pattern renders badly at some zoom.
            let casing = GMSPolyline(path: path)
            casing.strokeColor = UIColor(Theme.google).withAlphaComponent(0.35)
            casing.strokeWidth = Self.planCasingWidth
            casing.zIndex = 1
            casing.map = view

            let line = GMSPolyline(path: path)
            line.strokeWidth = Self.planLineWidth
            line.zIndex = 2
            // Dashed, like the Apple surface: alternating plan-orange and
            // gap. The lengths are metres on the ground, so they are scaled
            // to the route — a fixed short dash is sub-pixel on anything
            // longer than a few blocks and reads as no line at all.
            let dash = Self.dashMeters(for: plan.polyline.lengthMeters)
            line.spans = GMSStyleSpans(
                path,
                [GMSStrokeStyle.solidColor(UIColor(Theme.google)), GMSStrokeStyle.solidColor(.clear)],
                [NSNumber(value: dash.on), NSNumber(value: dash.off)],
                .rhumb
            )
            line.map = view
        }
        if let reroute = scene.drawableReroute(for: Self.provider) {
            let line = GMSPolyline(path: Self.path(reroute.polyline.coordinates))
            line.strokeColor = UIColor(Theme.pro)
            line.strokeWidth = Self.planLineWidth
            line.zIndex = 3
            line.map = view
        }
        for route in scene.routes {
            let line = GMSPolyline(path: Self.path(route.polyline.coordinates))
            line.strokeColor = UIColor(Theme.routeColor(rank: route.rank))
            line.strokeWidth = 4
            line.zIndex = 3
            line.map = view
        }
        if scene.trail.count >= 2 {
            let line = GMSPolyline(path: Self.path(scene.trail))
            line.strokeColor = UIColor(scene.offPlan ? Theme.win : Theme.route)
            line.strokeWidth = Self.trailWidth
            line.zIndex = 4
            line.map = view
        }
        if let end = scene.destination(for: Self.provider) {
            let marker = GMSMarker(position: CLLocationCoordinate2D(latitude: end.latitude, longitude: end.longitude))
            marker.title = scene.destinationName ?? "Destination"
            marker.map = view
        }

        frame(view, coordinator: context.coordinator)
    }

    private func frame(_ view: GMSMapView, coordinator: Coordinator) {
        switch scene.camera {
        case .followUser:
            // The SDK's own fix usually lands before the app's, and a nil
            // one used to leave the camera parked on the country view.
            guard let target = view.myLocation?.coordinate ?? scene.userLocation.map({
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }) else { return }
            // Follow at the zoom the driver is actually using. Forcing a
            // zoom every tick undid any pinch a second later, which reads
            // as being locked into a keyhole.
            let zoom = Self.followZoom(applied: coordinator.appliedZoom, current: view.camera.zoom)
            let course = view.myLocation.map { $0.course >= 0 ? $0.course : view.camera.bearing }
            view.animate(to: GMSCameraPosition(
                target: target, zoom: zoom, bearing: course ?? view.camera.bearing, viewingAngle: 0
            ))
            coordinator.appliedZoom = zoom
            LastMapCenter.save(Coordinate(latitude: target.latitude, longitude: target.longitude))
        case .fitContent:
            let planIDs = scene.drawablePlans(for: Self.provider).map(\.id) + scene.routes.map(\.id)
            guard coordinator.framedForCamera != scene.camera || coordinator.framedPlanIDs != planIDs else { return }
            let coordinates = scene.allCoordinates(for: Self.provider)
            guard let first = coordinates.first else {
                // Nothing drawn: settle over the driver. The SDK's own
                // fix counts — it is what puts the blue dot on screen, and
                // it often lands before the app's. Without either, leave
                // the marks unset so the next update retries.
                let mine = scene.fallbackCenter(for: Self.provider).map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                guard let here = mine ?? view.myLocation?.coordinate else { return }
                view.animate(to: GMSCameraPosition(
                    latitude: here.latitude, longitude: here.longitude, zoom: Self.aroundDriverZoom
                ))
                coordinator.appliedZoom = Self.aroundDriverZoom
                LastMapCenter.save(Coordinate(latitude: here.latitude, longitude: here.longitude))
                coordinator.framedForCamera = scene.camera
                coordinator.framedPlanIDs = planIDs
                return
            }
            var bounds = GMSCoordinateBounds(
                coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
            )
            for c in coordinates {
                bounds = bounds.includingCoordinate(CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude))
            }
            view.animate(with: GMSCameraUpdate.fit(bounds, withPadding: 40))
            coordinator.framedForCamera = scene.camera
            coordinator.framedPlanIDs = planIDs
        }
    }

    /// Neighbourhood scale, matching the Apple surface's empty-scene view.
    static let aroundDriverZoom: Float = 13
    /// Close enough to read the next turn, when following.
    nonisolated static let drivingZoom: Float = 16
    /// A pinch is far larger than this; anything smaller is an animation
    /// still settling between ticks, not the driver.
    nonisolated static let zoomDriftTolerance: Float = 0.25

    /// The zoom to follow at: the driver's, once they have chosen one.
    nonisolated static func followZoom(applied: Float?, current: Float) -> Float {
        guard let applied else { return drivingZoom }
        return abs(current - applied) < zoomDriftTolerance ? applied : current
    }

    /// The plan's dashes, and the ribbon beneath them. The ribbon has to
    /// be wider than the line or it is not a casing.
    nonisolated static let planLineWidth: CGFloat = 6
    nonisolated static let planCasingWidth: CGFloat = 11
    /// The driven trail sits above both and should still read as the
    /// heavier line.
    nonisolated static let trailWidth: CGFloat = 7

    /// Dash lengths in metres for a route of `length` metres: about forty
    /// dashes along the whole line, so the pattern stays visible whether
    /// the drive is a mile or fifty, with a floor for very short hops.
    nonisolated static func dashMeters(for length: Double) -> (on: Double, off: Double) {
        let segment = max(40, length / 40)
        return (on: segment * 0.6, off: segment * 0.4)
    }

    private static func path(_ coordinates: [Coordinate]) -> GMSMutablePath {
        let path = GMSMutablePath()
        for c in coordinates {
            path.add(CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude))
        }
        return path
    }
}
