import Foundation
import RouteWarriorKit

enum RoutesClientError: Error {
    /// No API key configured — the app runs keyless and trips simply carry
    /// no comparison (FR-6 fallback). Never fatal.
    case noAPIKey
    case badResponse(Int)
    /// The provider answered with no route at all.
    case noRoutes
}

/// The production RoutesProviding: Google Routes API computeRoutes v2.
/// Response parsing lives in the kit (`GoogleRoutes`); this only does the
/// HTTP. The key ships via the GoogleRoutesAPIKey Info.plist entry —
/// injected at build time, bundle-ID-restricted on Google's side, never
/// committed (SPEC §2.4).
struct GoogleRoutesClient: RoutesProviding {
    var apiKey: String
    var session: URLSession = .shared

    static var configuredKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "GoogleRoutesAPIKey") as? String) ?? ""
    }

    func computeSnapshot(
        from origin: Coordinate,
        to destination: Coordinate,
        destinationPlaceID: UUID?
    ) async throws -> PlanSnapshot {
        guard !apiKey.isEmpty else { throw RoutesClientError.noAPIKey }

        var request = URLRequest(url: URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(GoogleRoutes.fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        request.timeoutInterval = 10 // a departure snapshot is now or never
        request.httpBody = try JSONEncoder().encode(Body(origin: origin, destination: destination))

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw RoutesClientError.badResponse(status) }
        return try GoogleRoutes.snapshot(
            fromResponseData: data,
            requestedAt: .now,
            destinationPlaceID: destinationPlaceID
        )
    }

    private struct Body: Encodable {
        struct Waypoint: Encodable {
            struct Location: Encodable {
                struct LatLng: Encodable {
                    var latitude: Double
                    var longitude: Double
                }

                var latLng: LatLng
            }

            var location: Location
        }

        var origin: Waypoint
        var destination: Waypoint
        var travelMode = "DRIVE"
        var routingPreference = "TRAFFIC_AWARE"
        var computeAlternativeRoutes = true

        init(origin: Coordinate, destination: Coordinate) {
            self.origin = Waypoint(location: .init(latLng: .init(
                latitude: origin.latitude, longitude: origin.longitude
            )))
            self.destination = Waypoint(location: .init(latLng: .init(
                latitude: destination.latitude, longitude: destination.longitude
            )))
        }
    }
}
