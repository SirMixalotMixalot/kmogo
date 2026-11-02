import Foundation
import Observation
import UIKit

/// Single source of truth for the game. All rules (distance credit, coins, arrivals,
/// explore runs, strict mode, transit, cheats) live here so they can be unit tested.
@MainActor
@Observable
final class AppStore {
    var state: GameState {
        didSet { save() }
    }

    /// Group run waiting to start (host created it, or opened from an invite link).
    var lobbyInvite: GroupInvite?
    /// Run to show the summary / share card for, right after finishing.
    var finishedRunID: UUID?
    /// City reached during the last run or ticket ride.
    var arrivedCity: City?
    var isRouting = false
    var isStartingGroup = false

    static let strictGrace: TimeInterval = 60
    static let coinsPerKm = 10.0
    /// Finish an explore run this close to a city and you've reached it.
    static let cityRadiusKm = 2.5
    static let cheatCode = "ROAMFAST"

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored var routeProvider: (Coordinate, Coordinate) async -> RouteResult
    @ObservationIgnored var placeNamer: (Coordinate) async -> String?
    @ObservationIgnored var notificationsEnabled: Bool
    @ObservationIgnored var clock: () -> Date = Date.init
    /// Follow-up work after a run (naming places, re-routing). Tests await it.
    @ObservationIgnored var pendingWork: Task<Void, Never>?

    nonisolated static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("roam-state-v2.json")
    }

    init(fileURL: URL? = AppStore.defaultURL,
         routeProvider: @escaping (Coordinate, Coordinate) async -> RouteResult = RouteService.route,
         placeNamer: @escaping (Coordinate) async -> String? = PlaceNamer.locality,
         notificationsEnabled: Bool = true) {
        self.fileURL = fileURL
        self.routeProvider = routeProvider
        self.placeNamer = placeNamer
        self.notificationsEnabled = notificationsEnabled
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(GameState.self, from: data) {
            state = decoded
        } else {
            state = GameState()
        }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
        } catch {
            print("Roam: failed to save state: \(error)")
        }
    }

    // MARK: - Derived stats

    var pace: Int { state.profile?.paceSecPerKm ?? 360 }
    var totalKm: Double { state.runs.reduce(0) { $0 + $1.distanceKm } }
    var totalStudyTime: TimeInterval { state.runs.reduce(0) { $0 + $1.duration } }
    var longestRun: RunRecord? { state.runs.max { $0.duration < $1.duration } }
    var warp: Double { state.cheats.unlocked ? max(1, state.cheats.warp) : 1 }

    /// The runner's current spot on the world map.
    var currentCoordinate: Coordinate {
        state.currentLeg?.currentCoordinate ?? state.currentCity?.coordinate ?? Cities.waterloo.coordinate
    }

    func run(id: UUID) -> RunRecord? { state.runs.first { $0.id == id } }

    func durationFor(km: Double) -> TimeInterval { km * Double(pace) }

    // MARK: - Onboarding & settings

    func completeOnboarding(name: String, home: City, pace: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        state.profile = Profile(name: trimmed.isEmpty ? "Runner" : trimmed, paceSecPerKm: pace, homeCityID: home.id)
        state.currentCity = home
        collect(home)
    }

    func resetProgress() {
        Notifier.cancel([Notifier.finishID, Notifier.strictID])
        state = GameState()
        lobbyInvite = nil
        finishedRunID = nil
        arrivedCity = nil
    }

    func updateProfile(_ change: (inout Profile) -> Void) {
        guard var p = state.profile else { return }
        change(&p)
        state.profile = p
    }

    // MARK: - Journey

    func setDestination(_ city: City) async {
        guard state.currentLeg == nil, let origin = state.currentCity, origin.id != city.id else { return }
        isRouting = true
        defer { isRouting = false }
        let route = await routeProvider(origin.coordinate, city.coordinate)
        guard state.currentLeg == nil else { return }
        var leg = Leg(from: origin, to: city, path: route.path, totalKm: max(route.km, 0.01),
                      mode: route.mode, startedAt: clock())
        // Spend any distance banked from overshooting the previous city.
        let used = min(state.bankedKm, leg.totalKm)
        leg.progressKm = used
        state.bankedKm -= used
        if leg.isComplete {
            arrive(leg)
        } else {
            state.currentLeg = leg
        }
    }

    /// Switch destination, even mid-route: the new route starts from where you are now.
    func changeDestination(_ city: City) async {
        if let leg = state.currentLeg {
            guard leg.to.id != city.id else { return }
            isRouting = true
            state.currentLeg = nil
            if leg.progressKm > 0.01 {
                state.currentCity = await makeSpot(at: leg.currentCoordinate)
            }
        }
        await setDestination(city)
    }

    private func makeSpot(at c: Coordinate, name: String? = nil) async -> City {
        var resolved = name
        if resolved == nil { resolved = await placeNamer(c) }
        return City(id: "spot-\(UUID().uuidString)", name: resolved ?? "Trailside",
                    region: "Somewhere along the way", emoji: "📍", coordinate: c)
    }

    private func nearbyCity(_ c: Coordinate) -> City? {
        Cities.all
            .map { ($0, Geo.distanceKm($0.coordinate, c)) }
            .filter { $0.1 <= Self.cityRadiusKm }
            .min { $0.1 < $1.1 }?.0
    }

    /// Adds a city to the passport. Returns true if it's new.
    @discardableResult
    private func collect(_ city: City) -> Bool {
        guard !state.cities.contains(where: { $0.city.id == city.id }) else { return false }
        state.cities.append(CollectedCity(city: city, date: clock()))
        return true
    }

    private func arrive(_ leg: Leg) {
        var done = leg
        done.progressKm = done.totalKm
        done.arrivedAt = clock()
        state.completedLegs.append(done)
        state.currentLeg = nil
        state.currentCity = done.to
        collect(done.to)
        arrivedCity = done.to
    }

    /// Advances the runner along the current leg (overflow is banked).
    private func advance(by km: Double) {
        guard var leg = state.currentLeg else {
            state.bankedKm += km
            return
        }
        let moved = min(km, leg.remainingKm)
        leg.progressKm += moved
        state.bankedKm += km - moved
        if leg.isComplete {
            arrive(leg)
        } else {
            state.currentLeg = leg
        }
    }

    // MARK: - Planning runs

    /// The stretch of the journey a run of `km` would cover.
    func journeyRoute(km: Double) -> (route: [Coordinate], routeKm: Double)? {
        guard let leg = state.currentLeg, km > 0 else { return nil }
        let routeKm = min(km, leg.remainingKm)
        return (leg.slice(fromKm: leg.progressKm, toKm: leg.progressKm + routeKm), routeKm)
    }

    /// A real-world route from the runner toward any point (fit it with `Geo.fit`).
    func rawRoute(to target: Coordinate) async -> [Coordinate] {
        await routeProvider(currentCoordinate, target).path
    }

    /// Picks a point roughly `km` of running away in a compass direction.
    func exploreTarget(bearing: Double, km: Double) -> Coordinate {
        // Streets wind, so aim a bit short of the full distance.
        Geo.destination(from: currentCoordinate, bearing: bearing, km: km * 0.7)
    }

    // MARK: - Starting runs

    func startRun(km: Double) {
        guard state.activeRun == nil, let leg = state.currentLeg, let plan = journeyRoute(km: km) else { return }
        begin(ActiveRun(kind: .journey, startDate: clock(), duration: durationFor(km: km), warp: warp,
                        plannedKm: km, paceSecPerKm: pace, route: plan.route, routeKm: plan.routeKm,
                        legID: leg.id, startProgressKm: leg.progressKm))
    }

    /// A free run along `route` (already fit to `km`).
    func startExplore(route: [Coordinate], km: Double) {
        guard state.activeRun == nil, route.count >= 2, km > 0 else { return }
        begin(ActiveRun(kind: .explore, startDate: clock(), duration: durationFor(km: km), warp: warp,
                        plannedKm: km, paceSecPerKm: pace, route: route, routeKm: Track(route).totalKm))
    }

    func createInvite(km: Double, startsIn: TimeInterval) -> GroupInvite {
        GroupInvite(host: state.profile?.name ?? "Runner", start: clock().addingTimeInterval(startsIn),
                    km: km, paceSecPerKm: pace)
    }

    /// Joins a group run. Late joiners run the remaining part, finishing with everyone.
    /// Follows your journey if you have a destination, otherwise explores nearby.
    func startGroupRun(_ invite: GroupInvite) async {
        guard state.activeRun == nil, !isStartingGroup else { return }
        isStartingGroup = true
        defer { isStartingGroup = false }
        let start = max(clock(), invite.start)
        guard start < invite.end else { return }
        let km = invite.km * invite.end.timeIntervalSince(start) / invite.duration

        var run: ActiveRun
        if let leg = state.currentLeg, let plan = journeyRoute(km: km) {
            run = ActiveRun(kind: .journey, startDate: start, duration: 0, plannedKm: km,
                            paceSecPerKm: invite.paceSecPerKm, route: plan.route, routeKm: plan.routeKm,
                            legID: leg.id, startProgressKm: leg.progressKm)
        } else {
            let raw = await rawRoute(to: exploreTarget(bearing: .random(in: 0..<360), km: km))
            let route = Geo.fit(raw, toKm: km)
            run = ActiveRun(kind: .explore, startDate: start, duration: 0, plannedKm: km,
                            paceSecPerKm: invite.paceSecPerKm, route: route, routeKm: Track(route).totalKm)
        }
        guard state.activeRun == nil else { return }
        run.duration = invite.end.timeIntervalSince(start)
        run.group = invite
        lobbyInvite = nil
        begin(run)
    }

    private func begin(_ run: ActiveRun) {
        state.activeRun = run
        arrivedCity = nil
        guard notificationsEnabled else { return }
        Notifier.schedule(id: Notifier.finishID, at: run.realEndDate,
                          title: "🏁 Run complete!",
                          body: "You ran \(Fmt.km(run.plannedKm, digits: 1)) km. Come grab your run card.")
    }

    // MARK: - Finishing runs

    /// Ends the active run, crediting distance for the (study) time actually spent.
    func finishRun(at end: Date? = nil, completed: Bool? = nil) {
        guard let run = state.activeRun else { return }
        let realEnd = min(end ?? clock(), run.realEndDate)
        let elapsed = run.elapsed(at: realEnd)
        let fraction = run.duration > 0 ? elapsed / run.duration : 1
        let didComplete = completed ?? (fraction >= 1 - 1e-9)
        let km = run.plannedKm * fraction

        let track = Track(run.route)
        let path = run.donePath(at: realEnd, track: track)
        let endCoordinate = run.coordinate(at: realEnd, track: track)
        let leg = state.currentLeg

        let base = km * Self.coinsPerKm
        let coins = Int((didComplete ? base * 1.2 : base * 0.5).rounded())

        let from: String
        let to: String
        switch run.kind {
        case .journey:
            from = leg?.from.name ?? ""
            to = leg?.to.name ?? ""
        case .explore:
            from = (leg == nil || (leg?.progressKm ?? 0) < 0.01) ? (state.currentCity?.name ?? "Trailside") : "Trailside"
            to = ""
        }

        let record = RunRecord(startDate: run.startDate, endDate: run.startDate.addingTimeInterval(elapsed),
                               plannedKm: run.plannedKm, distanceKm: km, paceSecPerKm: run.paceSecPerKm,
                               path: path, legFrom: from, legTo: to,
                               completed: didComplete, groupHost: run.group?.host,
                               distractions: run.distractions, coins: coins, explore: run.kind == .explore)

        state.activeRun = nil
        state.coins += coins
        state.runs.insert(record, at: 0)
        finishedRunID = record.id
        if notificationsEnabled { Notifier.cancel([Notifier.finishID, Notifier.strictID]) }

        switch run.kind {
        case .journey:
            advance(by: km)
            pendingWork = Task { _ = await self.nameRun(record.id, start: nil, end: endCoordinate) }
        case .explore:
            let start = run.route.first
            let named = from == "Trailside"
            pendingWork = Task {
                await self.finishExplore(record.id, start: named ? start : nil, end: endCoordinate, moved: km > 0.01)
            }
        }
    }

    /// Reverse-geocodes a run's end (and optionally start), collecting new places.
    private func nameRun(_ id: UUID, start: Coordinate?, end: Coordinate) async -> String? {
        let endName = await placeNamer(end)
        var startName: String?
        if let start { startName = await placeNamer(start) }
        guard let i = state.runs.firstIndex(where: { $0.id == id }) else { return endName }
        if let endName {
            state.runs[i].endPlace = endName
            if !state.places.contains(where: { $0.name == endName }) {
                state.places.append(Place(name: endName, date: clock()))
            }
        }
        if let startName { state.runs[i].legFrom = startName }
        return endName
    }

    /// After an explore run the runner stays where they finished; the journey re-routes from there.
    private func finishExplore(_ id: UUID, start: Coordinate?, end: Coordinate, moved: Bool) async {
        let endName = await nameRun(id, start: start, end: end)
        guard moved else { return }
        let destination = state.currentLeg?.to

        if let city = nearbyCity(end) {
            if collect(city) { arrivedCity = city }
            if let leg = state.currentLeg, leg.to.id == city.id {
                arrive(leg)
                return
            }
            state.currentLeg = nil
            state.currentCity = city
        } else {
            state.currentLeg = nil
            state.currentCity = await makeSpot(at: end, name: endName)
        }
        if let destination, destination.id != state.currentCity?.id {
            await setDestination(destination)
        }
    }

    /// Called every second while running, and on launch.
    func tick() {
        guard let run = state.activeRun, run.backgroundedAt == nil else { return }
        if clock() >= run.realEndDate { finishRun(at: run.realEndDate, completed: true) }
    }

    // MARK: - Focus / strict mode

    func appDidBackground() {
        guard var run = state.activeRun, run.backgroundedAt == nil else { return }
        let now = clock()
        guard now < run.realEndDate else { return }
        run.backgroundedAt = now
        run.distractions += 1
        state.activeRun = run
        if notificationsEnabled, state.profile?.strictMode == true {
            Notifier.schedule(id: Notifier.strictID, at: now.addingTimeInterval(5),
                              title: "Your runner stopped! 🛑",
                              body: "Come back to Roam within a minute or your run ends.")
        }
    }

    func appDidBecomeActive() {
        guard var run = state.activeRun else { return }
        if notificationsEnabled { Notifier.cancel([Notifier.strictID]) }
        if let leftAt = run.backgroundedAt {
            run.backgroundedAt = nil
            state.activeRun = run
            let failAt = leftAt.addingTimeInterval(Self.strictGrace)
            if state.profile?.strictMode == true, clock() > failAt, failAt < run.realEndDate {
                // Strict mode: you stopped running when you left the app.
                finishRun(at: leftAt, completed: false)
                return
            }
        }
        tick()
    }

    // MARK: - Shop

    func canBuy(_ item: Transit) -> Bool {
        guard state.activeRun == nil, let leg = state.currentLeg, !leg.isComplete else { return false }
        return state.coins >= item.price
    }

    func buy(_ item: Transit) {
        guard canBuy(item), let leg = state.currentLeg else { return }
        let km = min(item.km ?? leg.remainingKm, leg.remainingKm)
        state.coins -= item.price
        state.transits.insert(TransitRecord(date: clock(), kind: item, km: km, legFrom: leg.from.name,
                                            legTo: leg.to.name,
                                            path: leg.slice(fromKm: leg.progressKm, toKm: leg.progressKm + km)), at: 0)
        advance(by: km)
    }

    // MARK: - Cheats 🕹️

    @discardableResult
    func redeem(code: String) -> Bool {
        guard code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == Self.cheatCode else { return false }
        state.cheats.unlocked = true
        if state.cheats.warp <= 1 { state.cheats.warp = 60 }
        return true
    }

    /// Instantly completes the active run as if the full time was studied.
    func cheatFinishRun() {
        guard state.cheats.unlocked, let run = state.activeRun else { return }
        finishRun(at: run.realEndDate, completed: true)
    }

    func cheatAddCoins() {
        guard state.cheats.unlocked else { return }
        state.coins += 1_000
    }

    func cheatTeleport() {
        guard state.cheats.unlocked, let leg = state.currentLeg else { return }
        advance(by: leg.remainingKm)
    }

    /// Back-fills a week of runs (ending with an 8-hour finals-season ultra).
    func addSampleRuns() async {
        guard state.activeRun == nil else { return }
        let realClock = clock
        defer { clock = realClock }
        var t = realClock().addingTimeInterval(-6 * 86_400)
        for km in [5.0, 10, 21.0975, 80] {
            clock = { t }
            if state.currentLeg != nil {
                startRun(km: km)
            } else {
                let raw = await rawRoute(to: exploreTarget(bearing: .random(in: 0..<360), km: km))
                startExplore(route: Geo.fit(raw, toKm: km), km: km)
            }
            guard let run = state.activeRun else { break }
            t = run.realEndDate
            finishRun()
            await pendingWork?.value
            t += 86_400
        }
        finishedRunID = nil
        arrivedCity = nil
    }

    // MARK: - Demo data (DEBUG launch arguments: -demo, -demoRun, -demoSummary)

    #if DEBUG
    /// Demo / marketing staging. Flags (all optional, fresh install only):
    ///   -demo                 seed a profile (+ a week of sample runs toward Montréal)
    ///   -demoHome <cityID>    start somewhere other than Waterloo
    ///   -noSamples            skip the destination + sample runs
    ///   -warp <n>             unlock cheats with an n× time warp
    ///   -exportCards          write the longest run's share cards to Documents
    ///   -demoSummary / -demoRun / -demoLobby   open those screens
    ///   -demoExploreTo <lat,lon>   start a 5K explore run toward a point
    func seedDemoIfRequested() async {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-demo"), state.profile == nil else { return }
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let home = value("-demoHome").flatMap(Cities.city(id:)) ?? Cities.waterloo
        completeOnboarding(name: "Patrick", home: home, pace: 360)
        state.cheats = Cheats(unlocked: false, warp: 1)
        if !args.contains("-noSamples") {
            await setDestination(Cities.city(id: "montreal")!)
            await addSampleRuns()
        }
        if let w = value("-warp").flatMap(Double.init) {
            state.cheats = Cheats(unlocked: true, warp: w)
        }
        if args.contains("-exportCards") { await exportShareCards() }
        if args.contains("-demoSummary") { finishedRunID = longestRun?.id }
        if args.contains("-demoRun") { startRun(km: 5) }
        if args.contains("-demoLobby") { lobbyInvite = createInvite(km: 5, startsIn: 90) }
        if let target = value("-demoExploreTo") {
            let parts = target.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                let raw = await rawRoute(to: Coordinate(lat: parts[0], lon: parts[1]))
                startExplore(route: Geo.fit(raw, toKm: 5), km: 5)
            }
        }
    }

    /// Writes the longest run's share cards to Documents (for marketing assets).
    private func exportShareCards() async {
        guard let record = longestRun else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let map = await MapSnapshot.make(path: record.path, size: ShareCardView.size, accent: Theme.uiOrange)
        for style in ShareStyle.allCases {
            let image = ShareCardRenderer.render(record, style: style, mapImage: map)
            try? image?.pngData()?.write(to: docs.appendingPathComponent("card-\(style.rawValue.lowercased()).png"))
        }
    }
    #endif
}
