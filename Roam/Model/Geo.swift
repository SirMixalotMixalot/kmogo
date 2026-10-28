import Foundation
import CoreLocation
import MapKit

/// A lightweight, Codable lat/lon pair (CLLocationCoordinate2D isn't Codable).
struct Coordinate: Codable, Hashable, Sendable {
    var lat: Double
    var lon: Double

    init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    init(_ c: CLLocationCoordinate2D) {
        lat = c.latitude
        lon = c.longitude
    }

    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var mapPoint: MKMapPoint { MKMapPoint(cl) }
}

enum Geo {
    static let earthRadiusKm = 6371.0088

    /// Great-circle (haversine) distance in kilometres.
    static func distanceKm(_ a: Coordinate, _ b: Coordinate) -> Double {
        let p1 = a.lat * .pi / 180
        let p2 = b.lat * .pi / 180
        let dp = p2 - p1
        let dl = (b.lon - a.lon) * .pi / 180
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(h)))
    }

    /// Linear interpolation – plenty accurate for the short segments of a route polyline.
    static func lerp(_ a: Coordinate, _ b: Coordinate, _ t: Double) -> Coordinate {
        Coordinate(lat: a.lat + (b.lat - a.lat) * t, lon: a.lon + (b.lon - a.lon) * t)
    }

    /// Points along the great circle between two coordinates ("as the crow flies").
    static func greatCircle(from a: Coordinate, to b: Coordinate, segments: Int = 128) -> [Coordinate] {
        let p1 = a.lat * .pi / 180, l1 = a.lon * .pi / 180
        let p2 = b.lat * .pi / 180, l2 = b.lon * .pi / 180
        let d = distanceKm(a, b) / earthRadiusKm
        guard d > 1e-9, segments > 1 else { return [a, b] }
        return (0...segments).map { i in
            let f = Double(i) / Double(segments)
            let A = sin((1 - f) * d) / sin(d)
            let B = sin(f * d) / sin(d)
            let x = A * cos(p1) * cos(l1) + B * cos(p2) * cos(l2)
            let y = A * cos(p1) * sin(l1) + B * cos(p2) * sin(l2)
            let z = A * sin(p1) + B * sin(p2)
            let lat = atan2(z, sqrt(x * x + y * y))
            let lon = atan2(y, x)
            return Coordinate(lat: lat * 180 / .pi, lon: lon * 180 / .pi)
        }
    }

    /// Initial compass bearing (0–360°) from a to b.
    static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let p1 = a.lat * .pi / 180, p2 = b.lat * .pi / 180
        let dl = (b.lon - a.lon) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The point `km` away from `a` along a compass bearing.
    static func destination(from a: Coordinate, bearing: Double, km: Double) -> Coordinate {
        let d = km / earthRadiusKm
        let t = bearing * .pi / 180
        let p1 = a.lat * .pi / 180, l1 = a.lon * .pi / 180
        let p2 = asin(sin(p1) * cos(d) + cos(p1) * sin(d) * cos(t))
        let l2 = l1 + atan2(sin(t) * sin(d) * cos(p1), cos(d) - sin(p1) * sin(p2))
        return Coordinate(lat: p2 * 180 / .pi, lon: l2 * 180 / .pi)
    }

    /// Makes a run of exactly `km` from a route: trims it if it's too long, or turns
    /// it into an out-and-back (and back again…) if it's too short.
    static func fit(_ path: [Coordinate], toKm km: Double) -> [Coordinate] {
        guard path.count >= 2, km > 0 else { return path }
        var combined = path
        var track = Track(combined)
        guard track.totalKm > 0.001 else { return path }
        var forward = false
        var laps = 0
        while track.totalKm < km - 1e-9, laps < 64 {
            let leg = forward ? path : path.reversed()
            combined += leg.dropFirst()
            forward.toggle()
            laps += 1
            track = Track(combined)
        }
        return track.slice(fromKm: 0, toKm: km)
    }

    /// Reduces a dense polyline to roughly `maxPoints` evenly spaced points, keeping both ends.
    static func thin(_ points: [Coordinate], maxPoints: Int) -> [Coordinate] {
        guard points.count > maxPoints, maxPoints >= 2 else { return points }
        let track = Track(points)
        let step = track.totalKm / Double(maxPoints - 1)
        guard step > 0 else { return [points[0], points[points.count - 1]] }
        var out = [points[0]]
        var lastKept = 0.0
        for i in 1..<(points.count - 1) where track.cumulativeKm[i] - lastKept >= step {
            out.append(points[i])
            lastKept = track.cumulativeKm[i]
        }
        out.append(points[points.count - 1])
        return out
    }
}

/// A polyline with precomputed cumulative distances, for "where am I after N km?" queries.
struct Track {
    let points: [Coordinate]
    let cumulativeKm: [Double]

    init(_ points: [Coordinate]) {
        self.points = points
        var cum: [Double] = []
        cum.reserveCapacity(points.count)
        var total = 0.0
        for i in points.indices {
            if i > 0 { total += Geo.distanceKm(points[i - 1], points[i]) }
            cum.append(total)
        }
        cumulativeKm = cum
    }

    var totalKm: Double { cumulativeKm.last ?? 0 }

    /// Largest index i (≤ count-2) such that cumulativeKm[i] <= km.
    private func segmentIndex(_ km: Double) -> Int {
        var lo = 0, hi = points.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cumulativeKm[mid] <= km { lo = mid } else { hi = mid }
        }
        return lo
    }

    func coordinate(atKm km: Double) -> Coordinate? {
        guard let first = points.first else { return nil }
        guard points.count > 1, totalKm > 0 else { return first }
        let k = min(max(km, 0), totalKm)
        let i = segmentIndex(k)
        let segLen = cumulativeKm[i + 1] - cumulativeKm[i]
        let t = segLen > 0 ? (k - cumulativeKm[i]) / segLen : 0
        return Geo.lerp(points[i], points[i + 1], t)
    }

    /// The sub-polyline between two distances along the track (inclusive, interpolated ends).
    func slice(fromKm: Double, toKm: Double) -> [Coordinate] {
        guard points.count > 1 else { return points }
        let a = min(max(min(fromKm, toKm), 0), totalKm)
        let b = min(max(max(fromKm, toKm), 0), totalKm)
        guard let start = coordinate(atKm: a), let end = coordinate(atKm: b) else { return [] }
        var out = [start]
        for i in points.indices where cumulativeKm[i] > a && cumulativeKm[i] < b {
            out.append(points[i])
        }
        out.append(end)
        return out
    }
}

extension Array where Element == Coordinate {
    var clCoordinates: [CLLocationCoordinate2D] { map(\.cl) }

    /// Bounding map rect, padded so the line doesn't touch the edges.
    func boundingMapRect(padding: Double = 0.25, minSize: Double = 2_000) -> MKMapRect {
        guard let first else { return .world }
        var minX = first.mapPoint.x, maxX = minX
        var minY = first.mapPoint.y, maxY = minY
        for c in self.dropFirst() {
            let p = c.mapPoint
            minX = Swift.min(minX, p.x); maxX = Swift.max(maxX, p.x)
            minY = Swift.min(minY, p.y); maxY = Swift.max(maxY, p.y)
        }
        let w = Swift.max(maxX - minX, minSize)
        let h = Swift.max(maxY - minY, minSize)
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        let pw = w * (1 + padding * 2), ph = h * (1 + padding * 2)
        return MKMapRect(x: cx - pw / 2, y: cy - ph / 2, width: pw, height: ph)
    }
}
