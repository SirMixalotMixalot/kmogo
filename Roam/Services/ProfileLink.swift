import Foundation

enum RoamUsername {
    static func normalized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
    }

    static func isValid(_ value: String) -> Bool {
        value.range(of: "^[a-z0-9][a-z0-9_]{2,19}$", options: .regularExpression) == value.startIndex..<value.endIndex
    }

    static func canSearch(_ value: String) -> Bool {
        value.range(of: "^[a-z0-9_]{2,20}$", options: .regularExpression) == value.startIndex..<value.endIndex
    }
}

struct ProfileLink: Identifiable, Equatable, Sendable {
    let username: String
    var id: String { username }
    var url: URL { URL(string: "https://kmogo.me/u/\(username)")! }

    init?(username: String) {
        let normalized = RoamUsername.normalized(username)
        guard RoamUsername.isValid(normalized) else { return nil }
        self.username = normalized
    }

    init?(url: URL) {
        guard url.user == nil, url.password == nil, url.port == nil else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        let candidate: String
        if url.scheme?.lowercased() == "https", url.host?.lowercased() == "kmogo.me",
           parts.count == 2, parts[0] == "u", url.path == "/u/\(parts[1])" || url.path == "/u/\(parts[1])/" {
            candidate = parts[1]
        } else if url.scheme?.lowercased() == "roam", url.host?.lowercased() == "profile",
                  parts.count == 1, url.path == "/\(parts[0])" || url.path == "/\(parts[0])/" {
            candidate = parts[0]
        } else {
            return nil
        }
        self.init(username: candidate)
    }
}
