import Foundation
import RouteWarriorKit

enum RoutesClientError: Error {
    /// No API key configured — the app runs keyless and trips simply carry
    /// no comparison (FR-6 fallback). Never fatal.
    case noAPIKey
    /// The server refused. `detail` carries Google's own message, which
    /// is the difference between "403" and "Routes API is not on this
    /// key's allowed list".
    case badResponse(Int, detail: String)
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
        // A key restricted to iOS apps identifies the caller by this
        // header. The Maps SDK sends it for us; a plain URLSession call
        // does not, which is how the same key can render Google's map and
        // still be refused a route (403).
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        request.timeoutInterval = 10 // a departure snapshot is now or never
        request.httpBody = try JSONEncoder().encode(Body(origin: origin, destination: destination))

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw RoutesClientError.badResponse(status, detail: Self.reason(in: data))
        }
        return try GoogleRoutes.snapshot(
            fromResponseData: data,
            requestedAt: .now,
            destinationPlaceID: destinationPlaceID
        )
    }

    /// Google answers a refusal with a JSON error whose message names the
    /// cause. A bare status is not actionable; the message is. Anything
    /// key-shaped is redacted first — this text is persisted to the
    /// recorder log and read on screen.
    static func reason(in data: Data) -> String {
        struct Failure: Decodable {
            struct Detail: Decodable { var message: String? }
            var error: Detail?
        }
        guard let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error?.message,
              !message.isEmpty
        else { return "" }
        return String(redactingKeys(in: message).prefix(160))
    }

    /// Google API keys are "AIza" plus 35 more characters. A refusal
    /// should never put one in a log a screenshot might reach.
    static func redactingKeys(in text: String) -> String {
        var result = text
        while let start = result.range(of: keyPrefix) {
            let end = result.index(start.lowerBound, offsetBy: keyLength, limitedBy: result.endIndex)
                ?? result.endIndex
            result.replaceSubrange(start.lowerBound..<end, with: "«key»")
        }
        return result
    }

    private static let keyPrefix = "AIza"
    /// "AIza" plus 35 more characters.
    private static let keyLength = 39

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
