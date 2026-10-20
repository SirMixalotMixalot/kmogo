import XCTest
@testable import Roam

final class GeoTests: XCTestCase {
    let waterloo = Cities.city(id: "waterloo")!.coordinate
    let toronto = Cities.city(id: "toronto")!.coordinate

    func testHaversineWaterlooToToronto() {
        XCTAssertEqual(Geo.distanceKm(waterloo, toronto), 94, accuracy: 3)
    }

    func testTrackInterpolationAndClamping() {
        let track = Track([Coordinate(lat: 0, lon: 0), Coordinate(lat: 0, lon: 1), Coordinate(lat: 0, lon: 2)])
        XCTAssertEqual(track.totalKm, 222.4, accuracy: 0.5)
        let mid = track.coordinate(atKm: track.totalKm / 2)!
        XCTAssertEqual(mid.lon, 1, accuracy: 1e-6)
        let quarter = track.coordinate(atKm: track.totalKm / 4)!
        XCTAssertEqual(quarter.lon, 0.5, accuracy: 1e-6)
        XCTAssertEqual(track.coordinate(atKm: -10)!.lon, 0)
        XCTAssertEqual(track.coordinate(atKm: 1e9)!.lon, 2)
    }

    func testSliceHasInterpolatedEndsAndInteriorPoints() {
        let track = Track([Coordinate(lat: 0, lon: 0), Coordinate(lat: 0, lon: 1), Coordinate(lat: 0, lon: 2)])
        let slice = track.slice(fromKm: track.totalKm * 0.25, toKm: track.totalKm * 0.75)
        XCTAssertEqual(slice.count, 3)
        XCTAssertEqual(slice[0].lon, 0.5, accuracy: 1e-6)
        XCTAssertEqual(slice[1].lon, 1, accuracy: 1e-6)
        XCTAssertEqual(slice[2].lon, 1.5, accuracy: 1e-6)
    }

    func testGreatCircleEndpoints() {
        let path = Geo.greatCircle(from: waterloo, to: toronto, segments: 10)
        XCTAssertEqual(path.count, 11)
        XCTAssertEqual(path.first!.lat, waterloo.lat, accuracy: 1e-6)
        XCTAssertEqual(path.last!.lon, toronto.lon, accuracy: 1e-6)
    }

    func testThinKeepsEndsAndCapsCount() {
        let dense = (0...5000).map { Coordinate(lat: 0, lon: Double($0) * 0.001) }
        let thin = Geo.thin(dense, maxPoints: 200)
        XCTAssertLessThanOrEqual(thin.count, 201)
        XCTAssertEqual(thin.first, dense.first)
        XCTAssertEqual(thin.last, dense.last)
    }

    func testLegMapsRealDistanceOntoThinnedPath() {
        // Real route is 200 km but the drawn path measures ~111 km: halfway should be the path midpoint.
        let leg = Leg(from: Cities.waterloo, to: Cities.waterloo,
                      path: [Coordinate(lat: 0, lon: 0), Coordinate(lat: 0, lon: 1)],
                      totalKm: 200, mode: .road, startedAt: .now)
        XCTAssertEqual(leg.coordinate(atProgressKm: 100).lon, 0.5, accuracy: 1e-6)
    }
}

final class GroupInviteTests: XCTestCase {
    func testURLRoundTrip() {
        let invite = GroupInvite(host: "Patrick & Co", start: Date(timeIntervalSince1970: 1_800_000_000.4),
                                 km: 5, paceSecPerKm: 360)
        let parsed = GroupInvite(url: invite.url)
        XCTAssertEqual(parsed, invite)
        XCTAssertEqual(parsed?.duration, 1800)
    }

    func testRejectsForeignOrBrokenLinks() {
        XCTAssertNil(GroupInvite(url: URL(string: "https://example.com/group?id=a")!))
        XCTAssertNil(GroupInvite(url: URL(string: "roam://group?id=abc&start=1&km=0&pace=360")!))
        XCTAssertNil(GroupInvite(url: URL(string: "roam://group?id=abc&km=5&pace=360")!))
    }

    func testFormatting() {
        XCTAssertEqual(Fmt.clock(3909), "1:05:09")
        XCTAssertEqual(Fmt.clock(1500), "25:00")
        XCTAssertEqual(Fmt.duration(8 * 3600), "8h")
        XCTAssertEqual(Fmt.duration(15180), "4h 13m")
        XCTAssertEqual(Fmt.pace(375), "6:15")
    }
}

@MainActor
final class AppStoreTests: XCTestCase {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var store: AppStore!

    /// Straight 0°→1° longitude line (~111 km) reported as a 100 km route.
    override func setUp() async throws {
        store = AppStore(fileURL: nil,
                         routeProvider: { a, b in RouteResult(path: [a, b], km: 100, mode: .foot) },
                         placeNamer: { _ in "Guelph" },
                         notificationsEnabled: false)
        store.clock = { [unowned self] in self.now }
        store.completeOnboarding(name: "Pat", home: Cities.waterloo, pace: 360)
        await store.setDestination(Cities.city(id: "toronto")!)
    }

    func testSetDestinationCreatesLeg() {
        XCTAssertEqual(store.state.currentLeg?.to.id, "toronto")
        XCTAssertEqual(store.state.currentLeg?.totalKm, 100)
        XCTAssertEqual(store.state.cities.map(\.id), ["waterloo"])
    }

    func testCompletedRunCreditsDistanceAndBonusCoins() async {
        let startCoins = store.state.coins
        store.startRun(km: 5)
        XCTAssertEqual(store.state.activeRun?.duration, 1800)
        now += 1800
        store.tick()
        XCTAssertNil(store.state.activeRun)
        let run = store.state.runs.first!
        XCTAssertTrue(run.completed)
        XCTAssertEqual(run.distanceKm, 5, accuracy: 1e-9)
        XCTAssertEqual(run.coins, 60)
        XCTAssertEqual(store.state.coins, startCoins + 60)
        XCTAssertEqual(store.state.currentLeg!.progressKm, 5, accuracy: 1e-9)
        XCTAssertEqual(store.finishedRunID, run.id)
        XCTAssertGreaterThan(run.path.count, 1)
        // Reverse geocoding lands asynchronously.
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(store.run(id: run.id)?.endPlace, "Guelph")
        XCTAssertEqual(store.state.places.map(\.name), ["Guelph"])
    }

    func testEndingEarlyCreditsPartialDistanceAndHalfCoins() {
        store.startRun(km: 10)
        now += 1800 // half of a 60 min run
        store.finishRun(completed: false)
        let run = store.state.runs.first!
        XCTAssertFalse(run.completed)
        XCTAssertEqual(run.distanceKm, 5, accuracy: 1e-9)
        XCTAssertEqual(run.coins, 25)
    }

    func testOvershootingArrivesAndBanksExtraKm() async {
        store.startRun(km: 120)
        now += 120 * 360
        store.tick()
        XCTAssertNil(store.state.currentLeg)
        XCTAssertEqual(store.state.currentCity?.id, "toronto")
        XCTAssertEqual(store.arrivedCity?.id, "toronto")
        XCTAssertEqual(store.state.cities.count, 2)
        XCTAssertEqual(store.state.bankedKm, 20, accuracy: 1e-9)
        // Banked km is spent on the next leg.
        await store.setDestination(Cities.city(id: "niagara")!)
        XCTAssertEqual(store.state.currentLeg!.progressKm, 20, accuracy: 1e-9)
        XCTAssertEqual(store.state.bankedKm, 0, accuracy: 1e-9)
    }

    func testStrictModeEndsRunWhenAwayTooLong() {
        store.updateProfile { $0.strictMode = true }
        store.startRun(km: 10)
        now += 600
        store.appDidBackground()
        now += 120
        store.appDidBecomeActive()
        let run = store.state.runs.first!
        XCTAssertFalse(run.completed)
        XCTAssertEqual(run.duration, 600, accuracy: 1e-6) // credited up to when they left
        XCTAssertEqual(run.distractions, 1)
    }

    func testRelaxedModeCountsDistractionButKeepsRunning() {
        store.startRun(km: 10)
        now += 600
        store.appDidBackground()
        now += 120
        store.appDidBecomeActive()
        XCTAssertEqual(store.state.activeRun?.distractions, 1)
        XCTAssertNil(store.state.activeRun?.backgroundedAt)
    }

    func testRunFinishingWhileBackgroundedCompletesOnReturn() {
        store.startRun(km: 5)
        now += 60
        store.appDidBackground()
        now += 3600
        store.appDidBecomeActive()
        XCTAssertNil(store.state.activeRun)
        XCTAssertTrue(store.state.runs.first!.completed)
        XCTAssertEqual(store.state.runs.first!.distanceKm, 5, accuracy: 1e-9)
    }

    func testLateJoinerFinishesWithGroup() {
        let invite = GroupInvite(host: "Sam", start: now - 600, km: 5, paceSecPerKm: 360)
        store.startGroupRun(invite)
        let run = store.state.activeRun!
        XCTAssertEqual(run.endDate, invite.end)
        XCTAssertEqual(run.plannedKm, 5 * (1200.0 / 1800.0), accuracy: 1e-9)
        XCTAssertEqual(run.group?.host, "Sam")
    }

    func testCannotJoinFinishedGroupRun() {
        store.startGroupRun(GroupInvite(host: "Sam", start: now - 4000, km: 5, paceSecPerKm: 360))
        XCTAssertNil(store.state.activeRun)
    }

    func testTicketsMoveRunnerAndPlaneArrives() {
        store.state.coins = 2000
        store.buy(.bus)
        XCTAssertEqual(store.state.currentLeg!.progressKm, 15, accuracy: 1e-9)
        XCTAssertEqual(store.state.coins, 1920)
        store.buy(.plane)
        XCTAssertNil(store.state.currentLeg)
        XCTAssertEqual(store.state.currentCity?.id, "toronto")
        XCTAssertEqual(store.state.transits.first?.km ?? 0, 85, accuracy: 1e-9)
        XCTAssertFalse(store.canBuy(.bus)) // no leg to ride
    }

    func testCannotBuyWithoutCoinsOrMidRun() {
        store.state.coins = 50
        XCTAssertFalse(store.canBuy(.bus))
        store.state.coins = 5000
        store.startRun(km: 5)
        XCTAssertFalse(store.canBuy(.bus))
    }

    func testStatePersistsToDisk() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("roam-test-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let a = AppStore(fileURL: url, routeProvider: { a, b in RouteResult(path: [a, b], km: 50, mode: .road) },
                         placeNamer: { _ in nil }, notificationsEnabled: false)
        a.completeOnboarding(name: "Pat", home: Cities.waterloo, pace: 300)
        await a.setDestination(Cities.city(id: "guelph")!)
        a.startRun(km: 5)
        let b = AppStore(fileURL: url, placeNamer: { _ in nil }, notificationsEnabled: false)
        XCTAssertEqual(b.state.profile?.paceSecPerKm, 300)
        XCTAssertEqual(b.state.currentLeg?.to.id, "guelph")
        XCTAssertEqual(b.state.activeRun?.plannedKm, 5)
    }
}
