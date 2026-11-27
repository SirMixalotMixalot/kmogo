import Foundation

struct CloudProfile: Decodable, Equatable, Sendable {
    let userID: UUID
    let displayName: String
    let username: String?
    let inviteCode: UUID
    let shareProgress: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case username
        case inviteCode = "invite_code"
        case shareProgress = "share_progress"
    }
}

struct RoamFriend: Decodable, Identifiable, Sendable {
    enum Status: String, Decodable, Sendable {
        case incoming, outgoing, accepted
    }

    let id: UUID
    let friendID: UUID
    let displayName: String
    let username: String?
    let status: Status
    let studySeconds: Int64?
    let virtualKm: Double?
    let virtualLatitude: Double?
    let virtualLongitude: Double?

    var coordinate: Coordinate? {
        guard status == .accepted, let virtualLatitude, let virtualLongitude else { return nil }
        return Coordinate(lat: virtualLatitude, lon: virtualLongitude)
    }

    enum CodingKeys: String, CodingKey {
        case id = "friendship_id"
        case friendID = "friend_id"
        case displayName = "display_name"
        case username
        case status
        case studySeconds = "study_seconds"
        case virtualKm = "virtual_km"
        case virtualLatitude = "virtual_latitude"
        case virtualLongitude = "virtual_longitude"
    }
}

struct RoamPublicProfile: Decodable, Identifiable, Sendable {
    enum Relationship: String, Decodable, Sendable {
        case ownProfile = "self", none, incoming, outgoing, accepted
    }

    let id: UUID
    let displayName: String
    let username: String
    let friendshipID: UUID?
    let relationship: Relationship
    let studySeconds: Int64?
    let virtualKm: Double?

    var link: ProfileLink? { ProfileLink(username: username) }

    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case displayName = "display_name"
        case username
        case friendshipID = "friendship_id"
        case relationship = "status"
        case studySeconds = "study_seconds"
        case virtualKm = "virtual_km"
    }
}

struct ProgressSnapshot: Encodable, Equatable, Sendable {
    let userID: UUID
    let studySeconds: Int64
    let virtualKm: Double
    let virtualLatitude: Double
    let virtualLongitude: Double

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case studySeconds = "study_seconds"
        case virtualKm = "virtual_km"
        case virtualLatitude = "virtual_latitude"
        case virtualLongitude = "virtual_longitude"
    }
}
