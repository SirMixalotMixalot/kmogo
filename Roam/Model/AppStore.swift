import Foundation
import Observation

/// Single source of truth for the game. All rules (distance credit, coins, arrivals,
/// strict mode, transit) live here so they can be unit tested without UI.
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

    static let strictGrace: TimeInterval = 60
    static let coinsPerKm = 10.0

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored var routeProvider: (Coordinate, Coordinate) async -> RouteResult
    @ObservationIgnored var placeNamer: (Coordinate) async -> String?
    @ObservationIgnored var notificationsEnabled: Bool
    @ObservationIgnored var clock: () -> Date = Date.init

    nonisolated static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("roam-state.json")
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
    var transitKm: Double { state.transits.reduce(0) { $0 + $1.km } }

    /// The runner's current spot on the world map.
    var currentCoordinate: Coordinate? {
        state.currentLeg?.currentCoordinate ?? state.currentCity?.coordinate
    }

    func run(id: UUID) -> RunRecord? { state.runs.first { $0.id == id } }

    // MARK: - Onboarding & settings

    func completeOnboarding(name: String, home: City, pace: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        state.profile = Profile(name: trimmed.isEmpty ? "Runner" : trimmed, paceSecPerKm: pace, homeCityID: home.id)
        state.currentCity = home
        if !state.cities.contains(where: { $0.city.id == home.id }) {
            state.cities.append(CollectedCity(city: home, date: clock()))
        }
    }

    func resetProgress() {
        Notifier.cancel([Notifier.finishID, Notifier.strictID])
        state = GameState()
        lobbyInvite = nil
        finishedRunID = nil
        arrivedCity = nil
    }

    // MARK: - Journey

    func setDestination(_ city: City) async {
        guard state.currentLeg == nil, let origin = state.currentCity, origin.id != city.id else { return }
        isRouting = true
        defer { isRouting = false }
        let route = await routeProvider(origin.coordinate, city.coordinate)
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

    private func arrive(_ leg: Leg) {
        var done = leg
        done.progressKm = done.totalKm
        done.arrivedAt = clock()
        state.completedLegs.append(done)
        state.currentLeg = nil
        state.currentCity = done.to
        if !state.cities.contains(where: { $0.city.id == done.to.id }) {
            state.cities.append(CollectedCity(city: done.to, date: clock()))
        }
        arrivedCity = done.to
    }

    /// Advances the runner along the current leg. Returns the km actually moved on the map.
    @discardableResult
    private func advance(by km: Double) -> Double {
        guard var leg = state.currentLeg else {
            state.bankedKm += km
            return 0
        }
        let moved = min(km, leg.remainingKm)
        leg.progressKm += moved
        state.bankedKm += km - moved
        if leg.isComplete {
            arrive(leg)
        } else {
            state.currentLeg = leg
        }
        return moved
    }

    // MARK: - Runs

    func durationFor(km: Double) -> TimeInterval { km * Double(pace) }

    func startRun(km: Double) {
        guard state.activeRun == nil, let leg = state.currentLeg, km > 0 else { return }
        let now = clock()
        let run = ActiveRun(startDate: now, endDate: now.addingTimeInterval(durationFor(km: km)),
                            plannedKm: km, paceSecPerKm: pace, startProgressKm: leg.progressKm, legID: leg.id)
        begin(run, leg: leg)
    }

    func createInvite(km: Double, startsIn: TimeInterval) -> GroupInvite {
        GroupInvite(host: state.profile?.name ?? "Runner", start: clock().addingTimeInterval(startsIn),
                    km: km, paceSecPerKm: pace)
    }

    /// Joins a group run. Late joiners run the remaining part, finishing with everyone.
    func startGroupRun(_ invite: GroupInvite) {
        guard state.activeRun == nil, let leg = state.currentLeg else { return }
        let now = clock()
        let start = max(now, invite.start)
        guard start < invite.end else { return }
        let fraction = invite.end.timeIntervalSince(start) / invite.duration
        let run = ActiveRun(startDate: start, endDate: invite.end, plannedKm: invite.km * fraction,
                            paceSecPerKm: invite.paceSecPerKm, startProgressKm: leg.progressKm,
                            legID: leg.id, group: invite)
        lobbyInvite = nil
        begin(run, leg: leg)
    }

    private func begin(_ run: ActiveRun, leg: Leg) {
        state.activeRun = run
        arrivedCity = nil
        guard notificationsEnabled else { return }
        Notifier.schedule(id: Notifier.finishID, at: run.endDate,
                          title: "🏁 Run complete!",
                          body: "You ran \(Fmt.km(run.plannedKm, digits: 1)) km toward \(leg.to.name). Come grab your run card.")
    }

    /// Ends the active run, crediting distance for the time actually spent.
    func finishRun(at end: Date? = nil, completed: Bool? = nil) {
        guard let run = state.activeRun else { return }
        let endDate = min(end ?? clock(), run.endDate)
        let fraction = run.fraction(at: endDate)
        let didComplete = completed ?? (fraction >= 1)
        let km = run.plannedKm * fraction

        let leg = state.currentLeg
        let path = leg.map { $0.slice(fromKm: run.startProgressKm, toKm: min(run.startProgressKm + km, $0.totalKm)) } ?? []
        let endCoordinate = path.last

        let base = km * Self.coinsPerKm
        let coins = Int((didComplete ? base * 1.2 : base * 0.5).rounded())

        let record = RunRecord(startDate: run.startDate, endDate: max(endDate, run.startDate),
                               plannedKm: run.plannedKm, distanceKm: km, paceSecPerKm: run.paceSecPerKm,
                               path: path, legFrom: leg?.from.name ?? "", legTo: leg?.to.name ?? "",
                               completed: didComplete, groupHost: run.group?.host,
                               distractions: run.distractions, coins: coins)

        state.activeRun = nil
        state.coins += coins
        state.runs.insert(record, at: 0)
        advance(by: km)
        finishedRunID = record.id

        if notificationsEnabled { Notifier.cancel([Notifier.finishID, Notifier.strictID]) }

        if let endCoordinate {
            Task { await self.nameEndPlace(record.id, at: endCoordinate) }
        }
    }

    private func nameEndPlace(_ id: UUID, at coordinate: Coordinate) async {
        guard let name = await placeNamer(coordinate),
              let i = state.runs.firstIndex(where: { $0.id == id }) else { return }
        state.runs[i].endPlace = name
        if !state.places.contains(where: { $0.name == name }) {
            state.places.append(Place(name: name, date: clock()))
        }
    }

    /// Called every second while running, and on launch.
    func tick() {
        guard let run = state.activeRun, run.backgroundedAt == nil else { return }
        if clock() >= run.endDate { finishRun(at: run.endDate, completed: true) }
    }

    // MARK: - Focus / strict mode

    func appDidBackground() {
        guard var run = state.activeRun, run.backgroundedAt == nil else { return }
        let now = clock()
        guard now < run.endDate else { return }
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
            if state.profile?.strictMode == true, clock() > failAt, failAt < run.endDate {
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
        state.transits.insert(TransitRecord(date: clock(), kind: item, km: km,
                                            legFrom: leg.from.name, legTo: leg.to.name), at: 0)
        advance(by: km)
    }

    // MARK: - Demo data (DEBUG launch arguments: -demo, -demoRun, -demoSummary)

    #if DEBUG
    func seedDemoIfRequested() async {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-demo"), state.profile == nil else { return }
        completeOnboarding(name: "Patrick", home: Cities.waterloo, pace: 360)
        await setDestination(Cities.city(id: "montreal")!)
        let realClock = clock
        var t = Date().addingTimeInterval(-6 * 86_400)
        for km in [5.0, 10, 21.0975, 80] { // ...ending with an 8 hour finals-season ultra
            clock = { t }
            startRun(km: km)
            t += km * Double(pace)
            finishRun()
            t += 86_400
        }
        clock = realClock
        finishedRunID = nil
        arrivedCity = nil
        if args.contains("-demoSummary") { finishedRunID = longestRun?.id }
        if args.contains("-demoRun") { startRun(km: 5) }
    }
    #endif

    // MARK: - Profile

    func updateProfile(_ change: (inout Profile) -> Void) {
        guard var p = state.profile else { return }
        change(&p)
        state.profile = p
    }
}
