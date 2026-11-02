import SwiftUI
import MapKit

enum SetupMode: String, Hashable { case journey, explore }

/// Where an explore run heads: a spot the user tapped, or a compass direction.
enum ExploreTarget: Equatable {
    case point(Coordinate)
    case bearing(Double)

    var key: String {
        switch self {
        case .point(let c): String(format: "p%.5f,%.5f", c.lat, c.lon)
        case .bearing(let b): String(format: "b%.0f", b)
        }
    }

    static var random: ExploreTarget { .bearing(.random(in: 0..<360)) }
}

struct RunSetupView: View {
    @Environment(AppStore.self) private var store
    @State private var preset: RunPreset = .fiveK
    @State private var customMinutes: Double = 60
    @State private var mode: SetupMode = ProcessInfo.processInfo.arguments.contains("-explore") ? .explore : .journey
    @State private var target: ExploreTarget = {
        // DEBUG staging: -exploreBearing <degrees> for a deterministic preview.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-exploreBearing"), i + 1 < args.count, let b = Double(args[i + 1]) {
            return .bearing(b)
        }
        return .random
    }()
    @State private var rawRoute: [Coordinate] = []
    @State private var rawKey = ""
    @State private var preview: [Coordinate] = []
    @State private var loadingRoute = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var bigMap = false
    @State private var showDestinations = false
    @State private var showGroup = false
    @State private var pendingInvite: GroupInvite?

    private var km: Double { preset.km ?? customMinutes * 60 / Double(store.pace) }
    private var leg: Leg? { store.state.currentLeg }
    private var effectiveMode: SetupMode { leg == nil ? .explore : mode }
    private var here: Coordinate { store.currentCoordinate }

    private var planKey: String {
        let legKey = leg.map { "\($0.id)-\(Int($0.progressKm * 1000))" } ?? "none"
        return "\(effectiveMode)-\(Int(km * 1000))-\(target.key)-\(legKey)-\(here.lat)"
    }

    /// Bearing targets are recomputed for each distance; tapped points are fixed.
    private func fetchKey(for t: ExploreTarget) -> String {
        if case .bearing = t { return "\(t.key)-\(Int(km * 1000))-\(here.lat)" }
        return "\(t.key)-\(here.lat)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    mapCard
                    statusRow
                    if leg != nil {
                        Picker("Mode", selection: $mode) {
                            Text("Toward \(leg?.to.name ?? "")").tag(SetupMode.journey)
                            Text("Explore").tag(SetupMode.explore)
                        }
                        .pickerStyle(.segmented)
                    }
                    modeHint
                    distancePicker
                    startButtons
                }
                .padding()
            }
            .navigationTitle("Roam")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { CoinBadge(coins: store.state.coins) }
            }
            .task(id: planKey) { await plan() }
            .sheet(isPresented: $showDestinations) { DestinationPicker() }
            .sheet(isPresented: $showGroup, onDismiss: {
                // Hand off to the full-screen lobby only after this sheet is gone.
                if let invite = pendingInvite {
                    pendingInvite = nil
                    store.lobbyInvite = invite
                }
            }) {
                GroupRunCreateView(defaultKm: km) { pendingInvite = $0 }
            }
        }
    }

    // MARK: - Planning

    private func plan() async {
        if effectiveMode == .journey {
            preview = store.journeyRoute(km: km)?.route ?? []
            fitCamera()
            return
        }
        let key = fetchKey(for: target)
        if key != rawKey {
            // Debounce slider drags before hitting Apple Maps.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            loadingRoute = true
            let destination: Coordinate
            switch target {
            case .point(let c): destination = c
            case .bearing(let b): destination = store.exploreTarget(bearing: b, km: km)
            }
            let raw = await store.rawRoute(to: destination)
            loadingRoute = false
            guard !Task.isCancelled else { return }
            rawRoute = raw
            rawKey = key
        }
        preview = Geo.fit(rawRoute, toKm: km)
        fitCamera()
    }

    private func fitCamera() {
        let pts = preview.count >= 2 ? preview : [here]
        withAnimation(.easeInOut(duration: 0.6)) {
            camera = .rect(pts.boundingMapRect(padding: 0.3, minSize: 1_500))
        }
    }

    /// Whether the tapped point is closer than the chosen distance (so it's an out-and-back).
    private var isOutAndBack: Bool {
        guard effectiveMode == .explore, rawRoute.count >= 2 else { return false }
        return Track(rawRoute).totalKm < km - 0.05
    }

    // MARK: - Map

    private var mapCard: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let leg {
                    MapPolyline(coordinates: leg.path.clCoordinates)
                        .stroke(.gray.opacity(0.6), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 6]))
                    Marker(leg.to.name, systemImage: "flag.checkered", coordinate: leg.to.coordinate.cl).tint(.gray)
                }
                if preview.count >= 2 {
                    MapPolyline(coordinates: preview.clCoordinates)
                        .stroke(.white, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: preview.clCoordinates)
                        .stroke(Theme.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    if let end = preview.last, !isOutAndBack {
                        Annotation("Finish", coordinate: end.cl) {
                            Image(systemName: "flag.checkered").font(.caption.bold()).padding(5)
                                .background(.white, in: Circle()).shadow(radius: 2)
                        }
                    }
                }
                if effectiveMode == .explore, case .point(let c) = target {
                    Marker("Run here", systemImage: "mappin", coordinate: c.cl).tint(Theme.orange)
                }
                Annotation("You", coordinate: here.cl) { RunnerDot(size: 28) }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
                MapPitchToggle()
            }
            .onTapGesture { screenPoint in
                guard let c = proxy.convert(screenPoint, from: .local) else { return }
                mode = .explore
                target = .point(Coordinate(c))
            }
        }
        .frame(height: bigMap ? 520 : 330)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .topLeading) {
            if loadingRoute {
                Label("Finding a route…", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(10)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 8) {
                mapButton(bigMap ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                    withAnimation(.spring) { bigMap.toggle() }
                }
                mapButton("scope") { fitCamera() }
            }
            .padding(10)
        }
    }

    private func mapButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.bold()).frame(width: 40, height: 40)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status

    @ViewBuilder private var statusRow: some View {
        if let leg {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(leg.from.emoji) \(leg.from.name) → \(leg.to.name) \(leg.to.emoji)")
                        .font(.subheadline.bold()).lineLimit(1)
                    Spacer()
                    Button("Change") { showDestinations = true }.font(.subheadline)
                }
                LegProgressBar(fraction: leg.fraction)
                Text("\(Fmt.km(leg.progressKm, digits: 1)) of \(Fmt.km(leg.totalKm, digits: 1)) km · \(Fmt.duration(store.durationFor(km: leg.remainingKm))) of study to go")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else if let city = store.state.currentCity {
            HStack {
                Text("\(city.emoji) You're in \(city.name)").font(.headline)
                Spacer()
                Button {
                    showDestinations = true
                } label: {
                    Label("Pick a city", systemImage: "mappin.and.ellipse")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder private var modeHint: some View {
        if effectiveMode == .explore {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "hand.tap.fill").foregroundStyle(Theme.orange)
                Text(exploreHint)
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    target = .random
                } label: {
                    Image(systemName: "dice.fill").font(.title3)
                }
                .buttonStyle(.bordered)
            }
        } else if let leg {
            Text("Follow the road toward \(leg.to.name). Your runner picks up right where you left off.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var exploreHint: String {
        guard isOutAndBack else { return "Tap anywhere on the map to run there, or roll a random direction." }
        let distance = Fmt.km(km, digits: 1)
        if case .point = target { return "Out-and-back: run to your pin and turn around to make \(distance) km." }
        return "Out-and-back: head out this way and turn around to make \(distance) km."
    }

    // MARK: - Distance

    private var distancePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Distance").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RunPreset.allCases) { p in
                        DistanceChip(title: p.title,
                                     subtitle: p.km.map { Fmt.duration(store.durationFor(km: $0)) } ?? Fmt.duration(customMinutes * 60),
                                     selected: p == preset)
                            .onTapGesture { withAnimation(.snappy) { preset = p } }
                    }
                }
            }
            if preset == .custom {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Study for \(Fmt.duration(customMinutes * 60))").font(.subheadline.bold())
                        Spacer()
                        Text("\(Fmt.km(km, digits: 1)) km").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $customMinutes, in: 10...600, step: 5)
                    Text(customMinutes >= 240 ? "Ultramarathon mode. Legendary. 🔥" : "Slide up to 10 hours for an ultra.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var startButtons: some View {
        VStack(spacing: 10) {
            Button {
                switch effectiveMode {
                case .journey: store.startRun(km: km)
                case .explore: store.startExplore(route: preview, km: km)
                }
            } label: {
                VStack(spacing: 2) {
                    Text(effectiveMode == .explore ? "Start explore run" : "Start run").font(.headline)
                    Text("\(Fmt.km(km, digits: 1)) km · \(Fmt.duration(store.durationFor(km: km))) of focus\(store.warp > 1 ? " · ⏩ \(Int(store.warp))×" : "")")
                        .font(.caption).opacity(0.85)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(preview.count < 2 || loadingRoute)

            Button {
                showGroup = true
            } label: {
                Label("Start a group run", systemImage: "person.3.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

struct DistanceChip: View {
    let title: String
    let subtitle: String
    let selected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.headline.weight(.heavy))
            Text(subtitle).font(.caption2).opacity(0.8)
        }
        .frame(minWidth: 64)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .foregroundStyle(selected ? .white : .primary)
        .background(selected ? AnyShapeStyle(Theme.orange) : AnyShapeStyle(.background.secondary),
                    in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
    }
}
