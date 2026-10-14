import Foundation

// MARK: - Places

struct City: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let region: String
    let emoji: String
    let coordinate: Coordinate
}

enum RouteMode: String, Codable, Sendable {
    case foot, road, greatCircle

    var label: String {
        switch self {
        case .foot: "On foot"
        case .road: "Along the highway"
        case .greatCircle: "As the crow flies"
        }
    }
}

/// One stretch of the journey between two cities. The runner's position on the
/// world map is `progressKm` along `path`.
struct Leg: Codable, Hashable, Identifiable {
    var id = UUID()
    var from: City
    var to: City
    var path: [Coordinate]
    var totalKm: Double
    var progressKm: Double = 0
    var mode: RouteMode
    var startedAt: Date
    var arrivedAt: Date?

    var remainingKm: Double { max(0, totalKm - progressKm) }
    var fraction: Double { totalKm > 0 ? min(1, progressKm / totalKm) : 1 }
    var isComplete: Bool { progressKm >= totalKm - 1e-6 }

    var track: Track { Track(path) }

    /// `path` may be thinned, so its measured length differs slightly from the real
    /// route length – map progress proportionally.
    private func trackKm(_ km: Double, _ t: Track) -> Double {
        totalKm > 0 ? km / totalKm * t.totalKm : 0
    }

    func coordinate(atProgressKm km: Double, track: Track? = nil) -> Coordinate {
        let t = track ?? self.track
        return t.coordinate(atKm: trackKm(km, t)) ?? from.coordinate
    }

    func slice(fromKm a: Double, toKm b: Double, track: Track? = nil) -> [Coordinate] {
        let t = track ?? self.track
        return t.slice(fromKm: trackKm(a, t), toKm: trackKm(b, t))
    }

    var currentCoordinate: Coordinate { coordinate(atProgressKm: progressKm) }
}

// MARK: - Runs

struct RunRecord: Codable, Hashable, Identifiable {
    var id = UUID()
    var startDate: Date
    var endDate: Date
    var plannedKm: Double
    var distanceKm: Double
    var paceSecPerKm: Int
    var path: [Coordinate]
    var legFrom: String
    var legTo: String
    var endPlace: String?
    var completed: Bool
    var groupHost: String?
    var distractions: Int
    var coins: Int

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }
    var isGroup: Bool { groupHost != nil }
    var routeLabel: String { "\(legFrom) → \(legTo)" }
}

/// The run currently in progress. Persisted so a relaunch resumes it.
struct ActiveRun: Codable, Equatable {
    var id = UUID()
    var startDate: Date
    var endDate: Date
    var plannedKm: Double
    var paceSecPerKm: Int
    var startProgressKm: Double
    var legID: UUID
    var group: GroupInvite?
    var distractions = 0
    var backgroundedAt: Date?

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    func fraction(at now: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(startDate) / duration))
    }

    func distanceKm(at now: Date) -> Double { plannedKm * fraction(at: now) }
    func remaining(at now: Date) -> TimeInterval { max(0, endDate.timeIntervalSince(now)) }
}

// MARK: - Group runs

/// A group run is fully described by its invite link – everyone who opens the link
/// runs the same distance and finishes at the same instant, no server required.
struct GroupInvite: Codable, Hashable, Identifiable {
    var id: String
    var host: String
    var start: Date
    var km: Double
    var paceSecPerKm: Int

    var duration: TimeInterval { km * Double(paceSecPerKm) }
    var end: Date { start.addingTimeInterval(duration) }

    init(id: String = GroupInvite.makeID(), host: String, start: Date, km: Double, paceSecPerKm: Int) {
        self.id = id
        self.host = host
        // Whole seconds so the link round-trips exactly.
        self.start = Date(timeIntervalSince1970: start.timeIntervalSince1970.rounded())
        self.km = km
        self.paceSecPerKm = paceSecPerKm
    }

    static func makeID() -> String {
        let chars = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    var url: URL {
        var c = URLComponents()
        c.scheme = "roam"
        c.host = "group"
        c.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "start", value: String(Int(start.timeIntervalSince1970))),
            URLQueryItem(name: "km", value: String(format: "%.3f", km)),
            URLQueryItem(name: "pace", value: String(paceSecPerKm)),
        ]
        return c.url!
    }

    init?(url: URL) {
        guard url.scheme == "roam", url.host == "group",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let id = value("id"), !id.isEmpty,
              let startS = value("start"), let start = TimeInterval(startS),
              let kmS = value("km"), let km = Double(kmS), km > 0,
              let paceS = value("pace"), let pace = Int(paceS), pace > 0
        else { return nil }
        self.init(id: id, host: value("host") ?? "A friend", start: Date(timeIntervalSince1970: start),
                  km: km, paceSecPerKm: pace)
    }

    var title: String { RunPreset.name(forKm: km) }

    var shareMessage: String {
        let time = start.formatted(date: .omitted, time: .shortened)
        return "🏃 Join my \(title) study run on Roam! We start at \(time) — \(Fmt.duration(duration)) of focus. Tap to join:"
    }
}

// MARK: - Shop

enum Transit: String, CaseIterable, Codable, Identifiable {
    case bus, train, plane

    var id: String { rawValue }

    var name: String {
        switch self {
        case .bus: "Bus ticket"
        case .train: "Train ticket"
        case .plane: "Plane ticket"
        }
    }

    var symbol: String {
        switch self {
        case .bus: "bus.fill"
        case .train: "tram.fill"
        case .plane: "airplane"
        }
    }

    var price: Int {
        switch self {
        case .bus: 80
        case .train: 300
        case .plane: 900
        }
    }

    /// km skipped; nil means "the rest of the current leg".
    var km: Double? {
        switch self {
        case .bus: 15
        case .train: 60
        case .plane: nil
        }
    }

    var blurb: String {
        switch self {
        case .bus: "Hop forward 15 km along your route."
        case .train: "Skip 60 km down the line."
        case .plane: "Fly straight to your destination."
        }
    }
}

struct TransitRecord: Codable, Hashable, Identifiable {
    var id = UUID()
    var date: Date
    var kind: Transit
    var km: Double
    var legFrom: String
    var legTo: String
}

struct CollectedCity: Codable, Hashable, Identifiable {
    var city: City
    var date: Date
    var id: String { city.id }
}

struct Place: Codable, Hashable, Identifiable {
    var name: String
    var date: Date
    var id: String { name }
}

// MARK: - Profile & state

struct Profile: Codable, Equatable {
    var name: String
    var paceSecPerKm: Int
    var homeCityID: String
    var strictMode: Bool = false
}

struct GameState: Codable {
    var profile: Profile?
    var coins = 150
    var currentCity: City?
    var currentLeg: Leg?
    var completedLegs: [Leg] = []
    /// Distance run past the end of a leg, applied to the next one.
    var bankedKm = 0.0
    var runs: [RunRecord] = []
    var transits: [TransitRecord] = []
    var cities: [CollectedCity] = []
    var places: [Place] = []
    var activeRun: ActiveRun?
}

// MARK: - Run presets

enum RunPreset: String, CaseIterable, Identifiable {
    case fiveK, tenK, half, marathon, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveK: "5K"
        case .tenK: "10K"
        case .half: "Half"
        case .marathon: "Marathon"
        case .custom: "Custom"
        }
    }

    var km: Double? {
        switch self {
        case .fiveK: 5
        case .tenK: 10
        case .half: 21.0975
        case .marathon: 42.195
        case .custom: nil
        }
    }

    static func name(forKm km: Double) -> String {
        for p in allCases where p.km != nil && abs(p.km! - km) < 0.01 {
            return p == .half ? "half marathon" : (p == .marathon ? "marathon" : p.title)
        }
        return String(format: "%.1f km", km)
    }
}

// MARK: - Formatting

enum Fmt {
    /// 1:05:09 or 25:00
    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded(.up)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    /// "4h 13m", "25 min", "45s"
    static func duration(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return "\(m) min" }
        return "\(s)s"
    }

    /// "6:00"
    static func pace(_ sec: Int) -> String { String(format: "%d:%02d", sec / 60, sec % 60) }

    static func km(_ km: Double, digits: Int = 2) -> String { String(format: "%.\(digits)f", km) }
}
