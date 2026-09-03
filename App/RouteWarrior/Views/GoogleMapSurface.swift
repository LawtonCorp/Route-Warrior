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
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(latitude: 39.5, longitude: -98.35, zoom: 3)
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
            let line = GMSPolyline(path: path)
            line.strokeWidth = 4
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
            line.strokeWidth = 4
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
            line.strokeWidth = 5
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
            // The SDK's own fix can lag the app's, and a nil one used to
            // leave the camera parked on the country view.
            if let location = view.myLocation {
                let bearing = location.course >= 0 ? location.course : 0
                view.animate(to: GMSCameraPosition(
                    target: location.coordinate, zoom: 16, bearing: bearing, viewingAngle: 0
                ))
            } else if let here = scene.userLocation {
                view.animate(to: GMSCameraPosition(
                    latitude: here.latitude, longitude: here.longitude, zoom: 16
                ))
            }
        case .fitContent:
            let planIDs = scene.drawablePlans(for: Self.provider).map(\.id) + scene.routes.map(\.id)
            guard coordinator.framedForCamera != scene.camera || coordinator.framedPlanIDs != planIDs else { return }
            let coordinates = scene.allCoordinates(for: Self.provider)
            guard let first = coordinates.first else {
                // Nothing drawn: settle over the driver instead of the
                // country view the SDK opens on. Without a fix yet, leave
                // the marks unset so the next one retries.
                guard let here = scene.fallbackCenter(for: Self.provider) else { return }
                view.animate(to: GMSCameraPosition(
                    latitude: here.latitude, longitude: here.longitude, zoom: Self.aroundDriverZoom
                ))
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
    private static let aroundDriverZoom: Float = 13

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
