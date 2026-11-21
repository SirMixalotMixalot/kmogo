import XCTest
@testable import Roam

@MainActor
final class AccountJourneyTests: XCTestCase {
    private var directory: URL!
    private var store: AppStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("roam-accounts-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = AppStore(fileURL: directory.appendingPathComponent("guest.json"),
                         placeNamer: { _ in nil }, notificationsEnabled: false)
    }

    override func tearDown() async throws {
        store = nil
        try FileManager.default.removeItem(at: directory)
    }

    func testAccountSwitchPreservesSeparateJourneysAndGuestData() throws {
        let alice = UUID()
        let bob = UUID()
        store.completeOnboarding(name: "Guest", home: Cities.waterloo, pace: 360)
        try store.useAccount(alice, importGuestProgress: true)
        store.updateProfile { $0.name = "Alice" }
        try store.useAccount(bob)
        XCTAssertNil(store.state.profile)
        store.completeOnboarding(name: "Bob", home: Cities.waterloo, pace: 300)

        try store.useAccount(alice)
        XCTAssertEqual(store.state.profile?.name, "Alice")
        XCTAssertEqual(store.state.profile?.paceSecPerKm, 360)
        try store.useAccount(bob)
        XCTAssertEqual(store.state.profile?.name, "Bob")
        try store.useAccount(nil)
        XCTAssertEqual(store.state.profile?.name, "Guest")
    }

    func testRestoringAccountPrefersExistingCacheOverGuestImport() throws {
        let userID = UUID()
        try store.useAccount(userID)
        store.completeOnboarding(name: "Saved account", home: Cities.waterloo, pace: 300)
        try store.useAccount(nil)
        store.completeOnboarding(name: "Guest", home: Cities.waterloo, pace: 360)
        try store.useAccount(userID, importGuestProgress: true)
        XCTAssertEqual(store.state.profile?.name, "Saved account")

        let reopened = AppStore(fileURL: directory.appendingPathComponent("guest.json"), notificationsEnabled: false)
        try reopened.useAccount(userID)
        XCTAssertEqual(reopened.state.profile?.name, "Saved account")
    }

    func testCorruptAccountCacheDoesNotReplaceCurrentJourney() throws {
        let userID = UUID()
        store.completeOnboarding(name: "Guest", home: Cities.waterloo, pace: 360)
        let cache = directory.appendingPathComponent("roam-account-\(userID.uuidString.lowercased()).json")
        try Data("invalid JSON".utf8).write(to: cache)
        XCTAssertThrowsError(try store.useAccount(userID))
        XCTAssertNil(store.accountID)
        XCTAssertEqual(store.state.profile?.name, "Guest")
    }

    func testRouteFinishingAfterAccountSwitchCannotChangeNewJourney() async throws {
        let started = expectation(description: "Route requested")
        var continuation: CheckedContinuation<RouteResult, Never>?
        store.completeOnboarding(name: "Guest", home: Cities.waterloo, pace: 360)
        store.routeProvider = { _, _ in
            await withCheckedContinuation {
                continuation = $0
                started.fulfill()
            }
        }
        let destination = Cities.city(id: "guelph")!
        let task = Task { await store.setDestination(destination) }
        await fulfillment(of: [started], timeout: 2)
        try store.useAccount(UUID())
        store.completeOnboarding(name: "New account", home: Cities.waterloo, pace: 300)
        continuation?.resume(returning: RouteResult(
            path: [Cities.waterloo.coordinate, destination.coordinate], km: 50, mode: .road
        ))
        await task.value
        XCTAssertNil(store.state.currentLeg)
        XCTAssertEqual(store.state.profile?.name, "New account")
    }

    func testProgressSnapshotIncludesActiveVirtualRunAndFreezesWhenBackgrounded() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        store.clock = { start }
        store.completeOnboarding(name: "Runner", home: Cities.waterloo, pace: 300)
        let route = [Coordinate(lat: 0, lon: 0), Coordinate(lat: 0, lon: 0.05)]
        store.startExplore(route: route, km: 5)
        let userID = UUID()
        let active = store.progressSnapshot(userID: userID, at: start.addingTimeInterval(300))
        XCTAssertEqual(active.studySeconds, 300)
        XCTAssertEqual(active.virtualKm, 1, accuracy: 0.001)
        XCTAssertGreaterThan(active.virtualLongitude, 0)

        store.clock = { start.addingTimeInterval(300) }
        store.appDidBackground()
        let backgrounded = store.progressSnapshot(userID: userID, at: start.addingTimeInterval(900))
        XCTAssertEqual(backgrounded, active)
    }

    func testResetWhileRoutingClearsLoadingAndDiscardsTheOldRoute() async {
        let started = expectation(description: "Route requested")
        var continuation: CheckedContinuation<RouteResult, Never>?
        store.completeOnboarding(name: "Runner", home: Cities.waterloo, pace: 360)
        store.routeProvider = { _, _ in
            await withCheckedContinuation {
                continuation = $0
                started.fulfill()
            }
        }
        let destination = Cities.city(id: "guelph")!
        let task = Task { await store.setDestination(destination) }
        await fulfillment(of: [started], timeout: 2)
        store.resetProgress()
        XCTAssertFalse(store.isRouting)
        continuation?.resume(returning: RouteResult(
            path: [Cities.waterloo.coordinate, destination.coordinate], km: 50, mode: .road
        ))
        await task.value
        XCTAssertNil(store.state.currentLeg)
        XCTAssertNil(store.state.profile)
    }
}

final class FriendDecodingTests: XCTestCase {
    func testPendingOrPrivateFriendsHaveNoMapPosition() throws {
        let data = Data("""
        [{"friendship_id":"00000000-0000-4000-8000-000000000001",
          "friend_id":"00000000-0000-4000-8000-000000000002",
          "display_name":"Pat","status":"incoming","study_seconds":null,"virtual_km":null,
          "virtual_latitude":43.5,"virtual_longitude":-80.5}]
        """.utf8)
        let friends = try JSONDecoder().decode([RoamFriend].self, from: data)
        XCTAssertNil(friends[0].coordinate)
        XCTAssertNil(friends[0].studySeconds)
    }
}
