import Foundation

enum Cities {
    private static func c(_ id: String, _ name: String, _ region: String, _ emoji: String, _ lat: Double, _ lon: Double) -> City {
        City(id: id, name: name, region: region, emoji: emoji, coordinate: Coordinate(lat: lat, lon: lon))
    }

    static let all: [City] = [
        c("waterloo", "Waterloo", "Ontario", "🎓", 43.4643, -80.5204),
        c("guelph", "Guelph", "Ontario", "🌳", 43.5448, -80.2482),
        c("london-on", "London", "Ontario", "🌲", 42.9849, -81.2453),
        c("hamilton", "Hamilton", "Ontario", "🏭", 43.2557, -79.8711),
        c("toronto", "Toronto", "Ontario", "🏙️", 43.6532, -79.3832),
        c("niagara", "Niagara Falls", "Ontario", "💦", 43.0896, -79.0849),
        c("barrie", "Barrie", "Ontario", "⛵", 44.3894, -79.6903),
        c("tobermory", "Tobermory", "Ontario", "🏝️", 45.2534, -81.6646),
        c("algonquin", "Algonquin Park", "Ontario", "🛶", 45.5372, -78.2634),
        c("kingston", "Kingston", "Ontario", "🏰", 44.2312, -76.4860),
        c("ottawa", "Ottawa", "Ontario", "🍁", 45.4215, -75.6972),
        c("montreal", "Montréal", "Québec", "🥯", 45.5019, -73.5674),
        c("quebec", "Québec City", "Québec", "❄️", 46.8139, -71.2080),
        c("halifax", "Halifax", "Nova Scotia", "⚓", 44.6488, -63.5752),
        c("winnipeg", "Winnipeg", "Manitoba", "🦬", 49.8951, -97.1384),
        c("calgary", "Calgary", "Alberta", "🤠", 51.0447, -114.0719),
        c("banff", "Banff", "Alberta", "🏔️", 51.1784, -115.5708),
        c("vancouver", "Vancouver", "British Columbia", "🌊", 49.2827, -123.1207),
        c("whistler", "Whistler", "British Columbia", "⛷️", 50.1163, -122.9574),
        c("buffalo", "Buffalo", "New York", "🍗", 42.8864, -78.8784),
        c("detroit", "Detroit", "Michigan", "🚗", 42.3314, -83.0458),
        c("chicago", "Chicago", "Illinois", "🌭", 41.8781, -87.6298),
        c("nyc", "New York", "New York", "🗽", 40.7128, -74.0060),
        c("boston", "Boston", "Massachusetts", "🦞", 42.3601, -71.0589),
        c("philly", "Philadelphia", "Pennsylvania", "🔔", 39.9526, -75.1652),
        c("dc", "Washington, D.C.", "District of Columbia", "🏛️", 38.9072, -77.0369),
        c("seattle", "Seattle", "Washington", "☕", 47.6062, -122.3321),
        c("sf", "San Francisco", "California", "🌉", 37.7749, -122.4194),
        c("la", "Los Angeles", "California", "🌴", 34.0522, -118.2437),
    ]

    static let waterloo = all[0]

    static func city(id: String) -> City? { all.first { $0.id == id } }

    /// Real routes are ~20–30% longer than the straight line; good enough for estimates.
    static let routeFactor = 1.25

    static func estimatedKm(from a: City, to b: City) -> Double {
        Geo.distanceKm(a.coordinate, b.coordinate) * routeFactor
    }
}
