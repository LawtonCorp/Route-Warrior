import Foundation

/// An ordered sequence of coordinates: a driven track's shape, a snapshot
/// route from Google, or a variant's representative line.
///
/// Encodes to and from Google's E5 encoded-polyline format (the Routes API
/// wire format, and a compact storage form). Segment-level projection math
/// uses an equirectangular projection around the query point, which is
/// accurate to centimeters at the sub-kilometer scale it is applied to.
public struct Polyline: Sendable, Equatable, Codable {
    public var coordinates: [Coordinate]

    public init(coordinates: [Coordinate]) {
        self.coordinates = coordinates
    }

    // MARK: Length

    public var lengthMeters: Double {
        guard coordinates.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<coordinates.count {
            total += Geo.distanceMeters(from: coordinates[i - 1], to: coordinates[i])
        }
        return total
    }

    /// Cumulative distance in meters from the start to each vertex.
    /// `first == 0`; `last == lengthMeters`.
    public var cumulativeDistances: [Double] {
        guard !coordinates.isEmpty else { return [] }
        var result = [0.0]
        result.reserveCapacity(coordinates.count)
        for i in 1..<coordinates.count {
            result.append(result[i - 1] + Geo.distanceMeters(from: coordinates[i - 1], to: coordinates[i]))
        }
        return result
    }

    // MARK: Google E5 encoding

    /// Decodes Google's encoded-polyline format. Returns nil on malformed
    /// input (truncated value, non-ASCII byte, dangling latitude).
    public static func decode(_ encoded: String) -> Polyline? {
        var coords: [Coordinate] = []
        var lat = 0
        var lon = 0
        var index = encoded.startIndex

        func nextValue() -> Int? {
            var result = 0
            var shift = 0
            while true {
                guard index < encoded.endIndex,
                      let ascii = encoded[index].asciiValue,
                      ascii >= 63
                else { return nil }
                index = encoded.index(after: index)
                let chunk = Int(ascii) - 63
                result |= (chunk & 0x1F) << shift
                shift += 5
                if chunk < 0x20 { break }
            }
            return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
        }

        while index < encoded.endIndex {
            guard let dLat = nextValue(), let dLon = nextValue() else { return nil }
            lat += dLat
            lon += dLon
            coords.append(Coordinate(latitude: Double(lat) / 1e5, longitude: Double(lon) / 1e5))
        }
        return Polyline(coordinates: coords)
    }

    public func encoded() -> String {
        var result = ""
        var prevLat = 0
        var prevLon = 0
        for c in coordinates {
            let lat = Int((c.latitude * 1e5).rounded())
            let lon = Int((c.longitude * 1e5).rounded())
            for delta in [lat - prevLat, lon - prevLon] {
                var value = delta < 0 ? ~(delta << 1) : (delta << 1)
                while value >= 0x20 {
                    result.append(Character(UnicodeScalar(UInt8(((value & 0x1F) | 0x20) + 63))))
                    value >>= 5
                }
                result.append(Character(UnicodeScalar(UInt8(value + 63))))
            }
            prevLat = lat
            prevLon = lon
        }
        return result
    }

    // MARK: Resampling

    /// Returns `count` points evenly spaced by arc length, endpoints
    /// preserved. Fewer than 2 source points, or `count < 2`, returns the
    /// polyline unchanged — there is no shape to resample.
    public func resampled(to count: Int) -> Polyline {
        guard coordinates.count >= 2, count >= 2 else { return self }
        let cumulative = cumulativeDistances
        let total = cumulative[cumulative.count - 1]
        guard total > 0 else {
            return Polyline(coordinates: Array(repeating: coordinates[0], count: count))
        }

        var result: [Coordinate] = []
        result.reserveCapacity(count)
        var segment = 0
        for i in 0..<count {
            let target = total * Double(i) / Double(count - 1)
            while segment < coordinates.count - 2, cumulative[segment + 1] < target {
                segment += 1
            }
            let segStart = cumulative[segment]
            let segLength = cumulative[segment + 1] - segStart
            let t = segLength > 0 ? (target - segStart) / segLength : 0
            let a = coordinates[segment]
            let b = coordinates[segment + 1]
            result.append(Coordinate(
                latitude: a.latitude + (b.latitude - a.latitude) * t,
                longitude: a.longitude + (b.longitude - a.longitude) * t
            ))
        }
        return Polyline(coordinates: result)
    }

    // MARK: Projection

    /// The nearest point on the polyline to `point`: its perpendicular
    /// distance in meters and its arc-length position along the line.
    /// Nil for a polyline with fewer than 2 points.
    public func nearestPoint(to point: Coordinate) -> (distanceMeters: Double, alongMeters: Double)? {
        guard coordinates.count >= 2 else { return nil }
        let refLat = point.latitude * .pi / 180
        let metersPerDegLat = Geo.earthRadiusMeters * .pi / 180
        let metersPerDegLon = metersPerDegLat * cos(refLat)

        func planar(_ c: Coordinate) -> (x: Double, y: Double) {
            (x: c.longitude * metersPerDegLon, y: c.latitude * metersPerDegLat)
        }

        let p = planar(point)
        let cumulative = cumulativeDistances
        var best: (distanceMeters: Double, alongMeters: Double)?

        for i in 0..<(coordinates.count - 1) {
            let a = planar(coordinates[i])
            let b = planar(coordinates[i + 1])
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let t: Double
            if lengthSquared > 0 {
                t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
            } else {
                t = 0
            }
            let cx = a.x + t * dx
            let cy = a.y + t * dy
            let distance = ((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)).squareRoot()
            let along = cumulative[i] + t * (cumulative[i + 1] - cumulative[i])
            if best == nil || distance < best!.distanceMeters {
                best = (distanceMeters: distance, alongMeters: along)
            }
        }
        return best
    }

    // MARK: Similarity

    /// Mean perpendicular deviation, in meters, of this line's resampled
    /// points from `other` — averaged in both directions so a short line
    /// hugging part of a long one still reads as different. This is the
    /// metric behind variant matching and followed-Google labeling.
    public func symmetricMeanDeviation(to other: Polyline, samples: Int = 64) -> Double? {
        guard coordinates.count >= 2, other.coordinates.count >= 2 else { return nil }

        func meanDeviation(from a: Polyline, to b: Polyline) -> Double {
            let sampled = a.resampled(to: samples).coordinates
            var total = 0.0
            for point in sampled {
                total += b.nearestPoint(to: point)?.distanceMeters ?? 0
            }
            return total / Double(sampled.count)
        }

        return (meanDeviation(from: self, to: other) + meanDeviation(from: other, to: self)) / 2
    }
}
