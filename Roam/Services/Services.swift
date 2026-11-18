import Foundation
import MapKit
import CoreLocation
import UserNotifications
import UIKit

// MARK: - Routing

struct RouteResult: Sendable {
    var path: [Coordinate]
    var km: Double
    var mode: RouteMode
}

/// Real-world routes from Apple Maps (no API key needed). Tries walking directions
/// first, falls back to driving for long legs, and finally to a great-circle line
/// (e.g. across water).
enum RouteService {
    static let maxPoints = 2_000

    static func route(from a: Coordinate, to b: Coordinate) async -> RouteResult {
        for (type, mode) in [(MKDirectionsTransportType.walking, RouteMode.foot), (.automobile, .road)] {
            if let route = await directions(from: a, to: b, type: type) {
                let pts = route.polyline.coordinates
                if pts.count >= 2 {
                    return RouteResult(path: Geo.thin(pts, maxPoints: maxPoints),
                                       km: route.distance / 1000, mode: mode)
                }
            }
        }
        let path = Geo.greatCircle(from: a, to: b, segments: 256)
        return RouteResult(path: path, km: Geo.distanceKm(a, b), mode: .greatCircle)
    }

    private static func directions(from a: Coordinate, to b: Coordinate, type: MKDirectionsTransportType) async -> MKRoute? {
        let request = MKDirections.Request()
        request.source = mapItem(a)
        request.destination = mapItem(b)
        request.transportType = type
        do {
            return try await MKDirections(request: request).calculate().routes.first
        } catch {
            return nil
        }
    }

    private static func mapItem(_ c: Coordinate) -> MKMapItem {
        if #available(iOS 26.0, *) {
            return MKMapItem(location: CLLocation(latitude: c.lat, longitude: c.lon), address: nil)
        } else {
            return MKMapItem(placemark: MKPlacemark(coordinate: c.cl))
        }
    }
}

extension MKPolyline {
    var coordinates: [Coordinate] {
        let pts = points()
        return (0..<pointCount).map { Coordinate(pts[$0].coordinate) }
    }
}

// MARK: - Reverse geocoding ("you made it to Guelph")

enum PlaceNamer {
    static func locality(at c: Coordinate) async -> String? {
        let location = CLLocation(latitude: c.lat, longitude: c.lon)
        if #available(iOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = try? await request.mapItems.first
            else { return nil }
            return item.addressRepresentations?.cityName ?? item.name
        } else {
            let marks = try? await CLGeocoder().reverseGeocodeLocation(location)
            guard let mark = marks?.first else { return nil }
            return mark.locality ?? mark.subAdministrativeArea ?? mark.name
        }
    }
}

extension PlaceNamer {
    /// Street the runner is on ("King St W"), for the live run header.
    static func street(at c: Coordinate) async -> String? {
        let marks = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.lat, longitude: c.lon))
        guard let mark = marks?.first else { return nil }
        if let street = mark.thoroughfare {
            return mark.locality.map { "\(street), \($0)" } ?? street
        }
        return mark.locality ?? mark.name
    }
}

// MARK: - Notifications

enum Notifier {
    static let finishID = "roam.run.finish"
    static let strictID = "roam.run.strict"

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func schedule(id: String, at date: Date, title: String, body: String) {
        let interval = date.timeIntervalSinceNow
        guard interval > 0.5 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel(_ ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}

// MARK: - Map snapshots for share cards

enum MapSnapshot {
    @MainActor
    static func make(path: [Coordinate], size: CGSize, accent: UIColor) async -> UIImage? {
        guard path.count >= 2 else { return nil }
        // Fit the route into a rect with the same aspect ratio as the card.
        var rect = path.boundingMapRect(padding: 0.35, minSize: 1_500)
        let aspect = size.width / size.height
        if rect.size.width / rect.size.height > aspect {
            let h = rect.size.width / aspect
            rect = MKMapRect(x: rect.origin.x, y: rect.midY - h / 2, width: rect.size.width, height: h)
        } else {
            let w = rect.size.height * aspect
            rect = MKMapRect(x: rect.midX - w / 2, y: rect.origin.y, width: w, height: rect.size.height)
        }
        // Push the route into the upper part of the card so stats don't cover it.
        rect = rect.offsetBy(dx: 0, dy: rect.size.height * 0.18)

        let options = MKMapSnapshotter.Options()
        options.mapRect = rect
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.pointOfInterestFilter = .excludingAll

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            snapshot.image.draw(at: .zero)
            let cg = ctx.cgContext
            let pts = path.map { snapshot.point(for: $0.cl) }
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.35).cgColor)
            cg.setLineWidth(9)
            cg.addLines(between: pts)
            cg.strokePath()
            cg.setStrokeColor(accent.cgColor)
            cg.setLineWidth(5)
            cg.addLines(between: pts)
            cg.strokePath()
            for (p, color) in [(pts.first!, UIColor.white), (pts.last!, accent)] {
                cg.setFillColor(color.cgColor)
                cg.fillEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
                cg.setStrokeColor(UIColor.black.cgColor)
                cg.setLineWidth(2)
                cg.strokeEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
            }
        }
    }
}
