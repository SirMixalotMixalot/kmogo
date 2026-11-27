import Foundation
import XCTest
@testable import Roam

final class ProfileLinkTests: XCTestCase {
    func testWebAndAppProfileLinksResolveTheSameUser() {
        let link = ProfileLink(username: " @Patrick_23 ")
        XCTAssertEqual(link?.url.absoluteString, "https://kmogo.me/u/patrick_23")
        XCTAssertEqual(ProfileLink(url: URL(string: "https://kmogo.me/u/Patrick_23/")!), link)
        XCTAssertEqual(ProfileLink(url: URL(string: "roam://profile/patrick_23")!), link)
    }

    func testProfileRoutingRejectsOtherHostsSchemesAndMalformedPaths() {
        for value in ["http://kmogo.me/u/patrick", "https://kmogo.me.evil.test/u/patrick",
                      "https://user@kmogo.me/u/patrick", "https://kmogo.me:443/u/patrick",
                      "https://kmogo.me/u/a", "https://kmogo.me/u/patrick/extra",
                      "https://kmogo.me//u/patrick", "roam://auth/recovery?code=test",
                      "roam://join/group", "roam://profile/pat%2Frick"] {
            XCTAssertNil(ProfileLink(url: URL(string: value)!), value)
        }
    }

    func testUsernameRulesExcludeWhitespaceUnicodeAndSearchWildcards() {
        XCTAssertTrue(RoamUsername.isValid("a_123"))
        XCTAssertTrue(RoamUsername.canSearch("pa"))
        for value in ["ab", "_abc", "ABC", "a b", "a/b", "a%bc", "abc\n", "ríta", String(repeating: "a", count: 21)] {
            XCTAssertFalse(RoamUsername.isValid(value), value)
        }
        XCTAssertFalse(RoamUsername.canSearch("p%"))
    }

    func testLegacyProfilesWithoutUsernamesStillDecode() throws {
        let data = Data("""
        {"user_id":"00000000-0000-4000-8000-000000000001","display_name":"Rita",
         "invite_code":"00000000-0000-4000-8000-000000000002","share_progress":false}
        """.utf8)
        let profile = try JSONDecoder().decode(CloudProfile.self, from: data)
        XCTAssertNil(profile.username)
        XCTAssertEqual(profile.displayName, "Rita")
    }

    func testSearchProfilesDecodeEveryRelationshipWithoutProgress() throws {
        for value in ["none", "incoming", "outgoing", "accepted", "self"] {
            let data = Data("""
            {"user_id":"00000000-0000-4000-8000-000000000001","display_name":"Mikayla",
             "username":"mikayla","friendship_id":null,"status":"\(value)"}
            """.utf8)
            let profile = try JSONDecoder().decode(RoamPublicProfile.self, from: data)
            XCTAssertEqual(profile.relationship.rawValue, value)
            XCTAssertNil(profile.studySeconds)
            XCTAssertEqual(profile.link?.url.absoluteString, "https://kmogo.me/u/mikayla")
        }
    }
}
