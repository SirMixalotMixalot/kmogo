import SwiftUI
import MapKit

struct ActiveRunView: View {
    @Environment(AppStore.self) private var store
    let run: ActiveRun
    private let track: Track

    init(run: ActiveRun) {
        self.run = run
        self.track = Track(run.route)
    }

    @State private var camera: MapCameraPosition = .automatic
    @State private var follow = true
    @State private var followDistance: Double = 650
    @State private var satellite = true
    @State private var showStreetView = true
    @State private var bigStreetView = false
    @State private var scene: MKLookAroundScene?
    @State private var sceneChecked = false
    @State private var lastLookup = Date.distantPast
    @State private var lookupKm = -1.0
    @State private var streetName: String?
    @State private var toast: String?
    @State private var lastWholeKm = -1
    @State private var confirmEnd = false

    private var leg: Leg? {
        guard run.kind == .journey, let leg = store.state.currentLeg, leg.id == run.legID else { return nil }
        return leg
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            ZStack {
                map(now: now).ignoresSafeArea()
                if follow {
                    RunnerSprite(size: 46, warp: run.warp)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                VStack(spacing: 10) {
                    header
                    if showStreetView { streetViewCard }
                    Spacer()
                    if let toast {
                        Text(toast)
                            .font(.headline)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Theme.orange, in: Capsule())
                            .foregroundStyle(.white)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    panel(now: now)
                }
            }
            .onChange(of: Int(now.timeIntervalSince1970)) { update(now: now) }
        }
        .task {
            lastWholeKm = Int(run.distanceKm(at: .now))
            update(now: .now, animated: false)
            while !Task.isCancelled {
                store.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: lastWholeKm)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .confirmationDialog("End your run early?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End run", role: .destructive) { store.finishRun(completed: false) }
            Button("Keep running", role: .cancel) {}
        } message: {
            Text("You'll keep the distance you've covered, but only earn half the coins.")
        }
    }

    // MARK: - Per-second updates

    private func update(now: Date, animated: Bool = true) {
        let here = run.coordinate(at: now, track: track)
        if follow {
            let cam = MapCamera(centerCoordinate: here.cl, distance: followDistance,
                                heading: run.heading(at: now, track: track), pitch: 62)
            if animated {
                withAnimation(.linear(duration: 1)) { camera = .camera(cam) }
            } else {
                camera = .camera(cam)
            }
        }

        // Kilometre splits.
        let whole = Int(run.distanceKm(at: now) + 1e-6)
        if whole > lastWholeKm, lastWholeKm >= 0 {
            showToast("🎉 KM \(whole) done · \(Fmt.pace(run.paceSecPerKm)) split")
        }
        lastWholeKm = max(lastWholeKm, whole)

        // Street view + street name, every ~200 m (and at most every 8 s of real time).
        let km = run.distanceKm(at: now)
        if km - lookupKm >= 0.2 || lookupKm < 0, now.timeIntervalSince(lastLookup) >= 8 {
            lookupKm = km
            lastLookup = now
            Task { await lookAround(at: here) }
        }
    }

    private func lookAround(at c: Coordinate) async {
        if showStreetView {
            let found = try? await MKLookAroundSceneRequest(coordinate: c.cl).scene
            // Keep the last good scene when there's no coverage for a moment.
            if let found { scene = found }
            sceneChecked = true
        }
        if let name = await PlaceNamer.street(at: c) { streetName = name }
    }

    private func showToast(_ text: String) {
        withAnimation(.spring) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut) { if toast == text { toast = nil } }
        }
    }

    private func overview() {
        withAnimation(.easeInOut(duration: 0.8)) {
            camera = .rect(run.route.boundingMapRect(padding: 0.3, minSize: 1_200))
        }
    }

    // MARK: - Map

    private func map(now: Date) -> some View {
        let done = run.donePath(at: now, track: track)
        let ahead = run.aheadPath(at: now, track: track)
        let here = run.coordinate(at: now, track: track)
        return Map(position: $camera) {
            if let leg {
                MapPolyline(coordinates: leg.path.clCoordinates)
                    .stroke(.gray.opacity(0.5), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 7]))
            }
            MapPolyline(coordinates: ahead.clCoordinates)
                .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            MapPolyline(coordinates: done.clCoordinates)
                .stroke(Theme.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            if let start = run.route.first {
                Annotation("", coordinate: start.cl) {
                    Circle().fill(.white).frame(width: 12, height: 12).overlay(Circle().stroke(.black, lineWidth: 2))
                }
            }
            if let finish = run.route.last {
                Annotation("Finish", coordinate: finish.cl) {
                    Image(systemName: "flag.checkered").font(.title3).padding(6)
                        .background(.white, in: Circle())
                }
            }
            if !follow {
                Annotation("", coordinate: here.cl) { RunnerSprite(size: 34, warp: run.warp) }
            }
        }
        .mapStyle(satellite ? .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
                            : .standard(elevation: .realistic))
        .mapControls { MapCompass() }
        .onMapCameraChange(frequency: .onEnd) { ctx in
            // Remember the user's pinch-zoom level while following.
            if follow { followDistance = min(max(ctx.camera.distance, 150), 30_000) }
        }
    }

    // MARK: - Overlays

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.bold()).lineLimit(1)
                if let streetName {
                    Text("Now on \(streetName)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            Spacer(minLength: 0)
            headerButton(follow ? "location.north.line.fill" : "location.north.line") {
                follow.toggle()
                if follow { update(now: .now) } else { overview() }
            }
            headerButton(satellite ? "globe.americas.fill" : "map") { satellite.toggle() }
            headerButton(showStreetView ? "binoculars.fill" : "binoculars") {
                showStreetView.toggle()
                if showStreetView { lookupKm = -1; lastLookup = .distantPast }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal)
    }

    private var title: String {
        if let host = run.group?.host {
            return host == store.state.profile?.name ? "Group run" : "Group run with \(host)"
        }
        if let leg { return "\(leg.from.name) → \(leg.to.name)" }
        return "Explore run"
    }

    private func headerButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.semibold)).frame(width: 30, height: 30)
        }
    }

    private var streetViewCard: some View {
        ZStack {
            if scene != nil {
                LookAroundPreview(scene: $scene, allowsNavigation: false, badgePosition: .bottomTrailing)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: sceneChecked ? "tree.fill" : "binoculars").font(.title2)
                    Text(sceneChecked ? "No street view here — just trees and open road." : "Looking around…")
                        .font(.caption).multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial)
            }
        }
        .frame(height: bigStreetView ? 260 : 130)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.spring) { bigStreetView.toggle() }
            } label: {
                Image(systemName: bigStreetView ? "chevron.up" : "chevron.down")
                    .font(.caption.bold()).padding(7).background(.thinMaterial, in: Circle())
            }
            .padding(6)
        }
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func panel(now: Date) -> some View {
        let fraction = run.fraction(at: now)
        return VStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(Fmt.clock(run.remaining(at: now)))
                    .font(.system(size: 60, weight: .heavy, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                HStack(spacing: 6) {
                    Text("of focus left")
                    if run.warp > 1 {
                        Text("⏩ \(Int(run.warp))× warp").font(.caption.bold()).foregroundStyle(Theme.orange)
                    }
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }
            LegProgressBar(fraction: fraction)
            HStack {
                StatTile(label: "Distance", value: Fmt.km(run.distanceKm(at: now)), unit: "/ \(Fmt.km(run.plannedKm, digits: 1)) km")
                StatTile(label: "Pace", value: Fmt.pace(run.paceSecPerKm), unit: "/km")
                StatTile(label: "Elapsed", value: Fmt.clock(run.elapsed(at: now).rounded(.down)))
            }
            if store.state.profile?.strictMode == true {
                Label("Strict mode: leaving Roam for over a minute ends your run.", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
            } else if run.distractions > 0 {
                Label("Left the app \(run.distractions)×. Stay focused!", systemImage: "eye.slash")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button(role: .destructive) {
                    confirmEnd = true
                } label: {
                    Text(fraction >= 1 ? "Finishing…" : "End run").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                if store.state.cheats.unlocked {
                    Button {
                        store.cheatFinishRun()
                    } label: {
                        Label("Finish", systemImage: "forward.end.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

/// The runner, bobbing along in stride. Cadence speeds up with time warp.
struct RunnerSprite: View {
    var size: CGFloat = 46
    var warp: Double = 1

    var body: some View {
        TimelineView(.animation) { ctx in
            let cadence = min(2.8 * sqrt(max(warp, 1)), 9)
            let t = ctx.date.timeIntervalSinceReferenceDate * cadence
            let stride = abs(sin(t * .pi))
            ZStack {
                Ellipse()
                    .fill(.black.opacity(0.28))
                    .frame(width: size * (0.75 - 0.15 * stride), height: size * 0.2)
                    .offset(y: size * 0.62)
                RunnerDot(size: size)
                    .offset(y: -stride * size * 0.2)
                    .rotationEffect(.degrees(sin(t * .pi) * 5))
            }
        }
    }
}

// MARK: - Group runs

struct GroupRunCreateView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let defaultKm: Double
    let onCreate: (GroupInvite) -> Void

    @State private var preset: RunPreset = .fiveK
    @State private var minutes: Double = 60
    @State private var startsIn = 2

    private var km: Double { preset.km ?? minutes * 60 / Double(store.pace) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Distance") {
                    Picker("Run", selection: $preset) {
                        ForEach(RunPreset.allCases) { Text($0.title).tag($0) }
                    }
                    if preset == .custom {
                        Stepper("\(Fmt.duration(minutes * 60))", value: $minutes, in: 10...600, step: 10)
                    }
                    LabeledContent("Study time", value: Fmt.duration(store.durationFor(km: km)))
                }
                Section {
                    Picker("Starts in", selection: $startsIn) {
                        ForEach([1, 2, 5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) }
                    }
                } footer: {
                    Text("Everyone who opens your invite starts and finishes at exactly the same time. Late joiners run the rest of the way with you.")
                }
                Section {
                    Button {
                        onCreate(store.createInvite(km: km, startsIn: TimeInterval(startsIn * 60)))
                        dismiss()
                    } label: {
                        Text("Create group run").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Group run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                if let match = RunPreset.allCases.first(where: { $0.km.map { abs($0 - defaultKm) < 0.01 } ?? false }) {
                    preset = match
                } else {
                    preset = .custom
                    minutes = (defaultKm * Double(store.pace) / 60 / 10).rounded() * 10
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct LobbyView: View {
    @Environment(AppStore.self) private var store
    let invite: GroupInvite

    private var isHost: Bool { invite.host == store.state.profile?.name }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            VStack(spacing: 24) {
                HStack {
                    Button("Leave") { store.lobbyInvite = nil }
                    Spacer()
                }
                Spacer()
                Image(systemName: "person.3.fill").font(.system(size: 54)).foregroundStyle(Theme.orange)
                    .symbolEffect(.pulse, options: .repeating)
                VStack(spacing: 6) {
                    Text(isHost ? "Your group run" : "\(invite.host)'s group run").font(.title.bold())
                    Text("\(invite.title) · \(Fmt.duration(invite.duration)) of focus")
                        .foregroundStyle(.secondary)
                    Text(store.state.currentLeg.map { "You'll run toward \($0.to.name)." } ?? "You'll explore around \(store.state.currentCity?.name ?? "you").")
                        .font(.caption).foregroundStyle(.secondary)
                }

                status(now: now)

                ShareLink(item: invite.url, message: Text(invite.shareMessage)) {
                    Label("Invite friends", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Spacer()
            }
            .padding()
            .onChange(of: Int(now.timeIntervalSince1970)) {
                if now >= invite.start, now < invite.end, !store.isStartingGroup {
                    Task { await store.startGroupRun(invite) }
                }
            }
        }
    }

    @ViewBuilder
    private func status(now: Date) -> some View {
        if now >= invite.end {
            Label("This run already finished.", systemImage: "flag.checkered").font(.headline)
        } else if now < invite.start {
            VStack(spacing: 4) {
                Text("Starts in").font(.headline).foregroundStyle(.secondary)
                Text(Fmt.clock(invite.start.timeIntervalSince(now)))
                    .font(.system(size: 56, weight: .heavy, design: .rounded).monospacedDigit())
                Text("at \(invite.start.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
            }
        } else {
            ProgressView("Starting…")
        }
    }
}
