import CoreLocation
import MapKit
import RouteWarriorKit
import SwiftUI

/// One view, two maps. Renders a `MapScene` on the surface the user chose
/// (FR-19): Apple's SwiftUI `Map` or Google's `GMSMapView`. Screens never
/// touch a provider type; they build a scene and hand it here.
struct MapSurfaceView: View {
    @Environment(MapSettings.self) private var mapSettings
    var scene: MapScene

    var body: some View {
        switch mapSettings.provider {
        case .apple:
            AppleMapSurface(scene: scene)
        case .google:
            GoogleMapSurface(scene: scene)
        }
    }
}

/// Apple's map: the v1 look, driven by the shared scene.
struct AppleMapSurface: View {
    var scene: MapScene
    @State private var camera: MapCameraPosition = .automatic
    @State private var framed = false

    private let provider = PlanSnapshot.Provider.appleMaps

    var body: some View {
        Map(position: $camera) {
            ForEach(scene.drawablePlans(for: provider), id: \.id) { plan in
                ForEach(Array(plan.alternates.enumerated()), id: \.offset) { _, alternate in
                    MapPolyline(coordinates: Self.cl(alternate.polyline.coordinates))
                        .stroke(Color.secondary.opacity(0.5), lineWidth: 3)
                }
                MapPolyline(coordinates: Self.cl(plan.polyline.coordinates))
                    .stroke(Theme.google, style: StrokeStyle(lineWidth: 4, dash: [8, 6]))
            }
            if let reroute = scene.drawableReroute(for: provider) {
                MapPolyline(coordinates: Self.cl(reroute.polyline.coordinates))
                    .stroke(Theme.pro, lineWidth: 4)
            }
            if scene.trail.count >= 2 {
                MapPolyline(coordinates: Self.cl(scene.trail))
                    .stroke(scene.offPlan ? Theme.win : Theme.route, lineWidth: 5)
            }
            if let end = scene.destination(for: provider) {
                Marker(scene.destinationName ?? "Destination", coordinate: CLLocationCoordinate2D(
                    latitude: end.latitude, longitude: end.longitude
                ))
            }
            UserAnnotation()
        }
        .mapStyle(.standard(showsTraffic: scene.showsTraffic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onAppear { frame() }
        .onChange(of: scene.camera) { framed = false; frame() }
        .onChange(of: scene.drawablePlans(for: provider).map(\.id)) { framed = false; frame() }
    }

    @MainActor
    private func frame() {
        switch scene.camera {
        case .followUser:
            camera = .userLocation(followsHeading: true, fallback: .automatic)
        case .fitContent:
            guard !framed else { return }
            let coordinates = scene.allCoordinates(for: provider)
            guard !coordinates.isEmpty else {
                camera = .automatic
                return
            }
            camera = .region(Self.region(fitting: coordinates))
            framed = true
        }
    }

    private static func cl(_ coordinates: [Coordinate]) -> [CLLocationCoordinate2D] {
        coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// A region around every coordinate with a third of padding.
    static func region(fitting coordinates: [Coordinate]) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                latitudinalMeters: 1_000, longitudinalMeters: 1_000
            )
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coordinates {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.01, (maxLat - minLat) * 1.35),
                longitudeDelta: max(0.01, (maxLon - minLon) * 1.35)
            )
        )
    }
}
