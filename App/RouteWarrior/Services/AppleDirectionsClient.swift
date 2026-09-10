import Foundation
import MapKit
import RouteWarriorKit

/// Apple's plan through MapKit directions (D-022, M7): free, keyless, and
/// no third-party SDK. MKRoute exposes one traffic-aware
/// `expectedTravelTime`, so a snapshot's static and traffic durations are
/// the same number — Apple does not say how much of its ETA is traffic,
/// and the kit's `trafficFactor` reads 1.0 for Apple plans. The route's
/// steps ride along as the plan's maneuvers (D-052): words, a line and a
/// distance each — MapKit gives no maneuver class, so the kit reads it
/// from the words.
struct AppleDirectionsClient: RoutesProviding {
    func computeSnapshot(
        from origin: Coordinate,
        to destination: Coordinate,
        destinationPlaceID: UUID?
    ) async throws -> PlanSnapshot {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: origin.latitude, longitude: origin.longitude
        )))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: destination.latitude, longitude: destination.longitude
        )))
        request.transportType = .automobile
        request.requestsAlternateRoutes = true

        let response = try await MKDirections(request: request).calculate()
        guard let primary = response.routes.first else { throw RoutesClientError.noRoutes }
        return PlanSnapshot(
            provider: .appleMaps,
            requestedAt: .now,
            destinationPlaceID: destinationPlaceID,
            polyline: Self.polyline(of: primary.polyline),
            distanceM: primary.distance,
            staticDuration: primary.expectedTravelTime,
            trafficDuration: primary.expectedTravelTime,
            alternates: response.routes.dropFirst().map { route in
                PlanSnapshot.AltRoute(
                    polyline: Self.polyline(of: route.polyline),
                    staticDuration: route.expectedTravelTime,
                    trafficDuration: route.expectedTravelTime,
                    steps: Self.steps(of: route)
                )
            },
            steps: Self.steps(of: primary)
        )
    }

    private static func steps(of route: MKRoute) -> [PlanStep] {
        route.steps.map { step in
            PlanStep(
                instruction: step.instructions,
                polyline: polyline(of: step.polyline),
                distanceM: step.distance
            )
        }
    }

    private static func polyline(of line: MKPolyline) -> Polyline {
        let points = line.points()
        var coordinates: [Coordinate] = []
        coordinates.reserveCapacity(line.pointCount)
        for index in 0..<line.pointCount {
            let coordinate = points[index].coordinate
            coordinates.append(Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        return Polyline(coordinates: coordinates)
    }
}
