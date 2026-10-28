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

    func testBearingAndDestinationRoundTrip() {
        XCTAssertEqual(Geo.bearing(from: Coordinate(lat: 0, lon: 0), to: Coordinate(lat: 0, lon: 1)), 90, accuracy: 1e-6)
        XCTAssertEqual(Geo.bearing(from: Coordinate(lat: 0, lon: 0), to: Coordinate(lat: 1, lon: 0)), 0, accuracy: 1e-6)
        let d = Geo.destination(from: waterloo, bearing: 45, km: 5)
        XCTAssertEqual(Geo.distanceKm(waterloo, d), 5, accuracy: 1e-6)
        XCTAssertEqual(Geo.bearing(from: waterloo, to: d), 45, accuracy: 0.1)
    }

    func testFitTrimsLongRoutes() {
        let path = [Coordinate(lat: 0, lon: 0), Coordinate(lat: 0, lon: 1)] // ~111 km
        let fit = Geo.fit(path, toKm: 5)
        XCTAssertEqual(Track(fit).totalKm, 5, accuracy: 1e-6)
        XCTAssertEqual(fit.first, path.first)
    }

    func testFitMakesOutAndBackForShortRoutes() {
        let path = [Coordinate(lat: 0, lon: 0), Coordinate(lat: 0, lon: 0.018)] // ~2 km
        let fit = Geo.fit(path, toKm: 5)
        XCTAssertEqual(Track(fit).totalKm, 5, accuracy: 1e-6)
        // 2 km out, 2 km back, 1 km out again.
        XCTAssertEqual(fit.last!.lon, 0.018 / 2, accuracy: 0.0005)
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

    func testLateJoinerFinishesWithGroup() async {
        let invite = GroupInvite(host: "Sam", start: now - 600, km: 5, paceSecPerKm: 360)
        await store.startGroupRun(invite)
        let run = store.state.activeRun!
        XCTAssertEqual(run.realEndDate, invite.end)
        XCTAssertEqual(run.plannedKm, 5 * (1200.0 / 1800.0), accuracy: 1e-9)
        XCTAssertEqual(run.group?.host, "Sam")
    }

    func testCannotJoinFinishedGroupRun() async {
        await store.startGroupRun(GroupInvite(host: "Sam", start: now - 4000, km: 5, paceSecPerKm: 360))
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

    // MARK: Explore runs

    func testExploreRunMovesRunnerAndReroutesJourney() async {
        let start = store.currentCoordinate
        let route = Geo.fit([start, Geo.destination(from: start, bearing: 0, km: 20)], toKm: 5)
        store.startExplore(route: route, km: 5)
        XCTAssertEqual(store.state.activeRun?.kind, .explore)
        now += 1800
        store.tick()
        await store.pendingWork?.value

        let run = store.state.runs.first!
        XCTAssertTrue(run.explore)
        XCTAssertEqual(run.distanceKm, 5, accuracy: 1e-9)
        XCTAssertEqual(run.routeLabel, "Waterloo → Guelph")
        // Runner now stands where the run ended, 5 km north…
        XCTAssertEqual(Geo.distanceKm(start, store.state.currentCity!.coordinate), 5, accuracy: 0.01)
        XCTAssertTrue(store.state.currentCity!.id.hasPrefix("spot-"))
        // …and the journey to Toronto re-routes from there, from scratch.
        XCTAssertEqual(store.state.currentLeg?.to.id, "toronto")
        XCTAssertEqual(store.state.currentLeg?.progressKm, 0)
        XCTAssertEqual(store.state.currentLeg?.from.id, store.state.currentCity?.id)
    }

    func testExploreRunEndingAtACityCollectsIt() async {
        let guelph = Cities.city(id: "guelph")!
        let route = [store.currentCoordinate, guelph.coordinate]
        let km = Track(route).totalKm
        store.startExplore(route: route, km: km)
        now += store.durationFor(km: km)
        store.tick()
        await store.pendingWork?.value
        XCTAssertEqual(store.state.currentCity?.id, "guelph")
        XCTAssertEqual(store.arrivedCity?.id, "guelph")
        XCTAssertTrue(store.state.cities.contains { $0.id == "guelph" })
        XCTAssertEqual(store.state.currentLeg?.from.id, "guelph") // still heading to Toronto
    }

    func testExploreWithoutDestinationJustMoves() async {
        store.state.currentLeg = nil
        let start = store.currentCoordinate
        store.startExplore(route: Geo.fit([start, Geo.destination(from: start, bearing: 180, km: 10)], toKm: 3), km: 3)
        now += 1080
        store.tick()
        await store.pendingWork?.value
        XCTAssertNil(store.state.currentLeg)
        XCTAssertEqual(Geo.distanceKm(start, store.currentCoordinate), 3, accuracy: 0.01)
    }

    func testChangeDestinationMidRouteStartsFromCurrentSpot() async {
        store.buy(.bus) // 15 km in
        let here = store.currentCoordinate
        await store.changeDestination(Cities.city(id: "niagara")!)
        XCTAssertEqual(store.state.currentLeg?.to.id, "niagara")
        XCTAssertEqual(store.state.currentLeg!.from.coordinate.lat, here.lat, accuracy: 1e-9)
        XCTAssertEqual(store.state.currentLeg?.progressKm, 0)
    }

    // MARK: Cheats

    func testCheatCodeUnlocksWarpAndInstantFinish() {
        XCTAssertFalse(store.redeem(code: "letmein"))
        XCTAssertFalse(store.state.cheats.unlocked)
        XCTAssertTrue(store.redeem(code: " roamfast "))
        XCTAssertEqual(store.warp, 60)

        store.startRun(km: 5)
        let run = store.state.activeRun!
        XCTAssertEqual(run.realEndDate.timeIntervalSince(run.startDate), 30, accuracy: 1e-9) // 30 min in 30 s
        now += 15
        XCTAssertEqual(run.distanceKm(at: now), 2.5, accuracy: 1e-9)
        store.cheatFinishRun()
        let record = store.state.runs.first!
        XCTAssertTrue(record.completed)
        XCTAssertEqual(record.duration, 1800, accuracy: 1e-9) // recorded as full study time
        XCTAssertEqual(record.distanceKm, 5, accuracy: 1e-9)
    }

    func testWarpedRunCompletesOnTickAfterRealSeconds() {
        store.redeem(code: "ROAMFAST")
        store.state.cheats.warp = 300
        store.startRun(km: 42.195)
        now += 42.195 * 360 / 300 + 0.1
        store.tick()
        XCTAssertNil(store.state.activeRun)
        XCTAssertEqual(store.state.runs.first!.duration, 42.195 * 360, accuracy: 0.01)
    }

    func testCheatsAreLockedByDefault() {
        let coins = store.state.coins
        store.cheatAddCoins()
        store.startRun(km: 5)
        store.cheatFinishRun()
        XCTAssertEqual(store.state.coins, coins)
        XCTAssertNotNil(store.state.activeRun)
        XCTAssertEqual(store.state.activeRun?.warp, 1)
    }

    func testSampleRunsBackfillHistory() async {
        store.redeem(code: "ROAMFAST")
        await store.addSampleRuns()
        XCTAssertEqual(store.state.runs.count, 4)
        XCTAssertEqual(store.longestRun?.duration ?? 0, 80 * 360, accuracy: 1e-6)
        XCTAssertLessThan(store.state.runs.map(\.startDate).max()!, now)
        XCTAssertNil(store.state.activeRun)
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
