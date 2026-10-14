import SwiftUI
import MapKit

struct ActiveRunView: View {
    @Environment(AppStore.self) private var store
    let run: ActiveRun

    @State private var camera: MapCameraPosition = .automatic
    @State private var confirmEnd = false
    @State private var follow = false

    private var leg: Leg? {
        guard let leg = store.state.currentLeg, leg.id == run.legID else { return nil }
        return leg
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            ZStack(alignment: .bottom) {
                map(now: now)
                    .ignoresSafeArea()
                VStack {
                    header
                    Spacer()
                    panel(now: now)
                }
            }
            .onChange(of: Int(now.timeIntervalSince1970)) {
                if follow, let leg {
                    let here = leg.coordinate(atProgressKm: run.startProgressKm + run.distanceKm(at: now))
                    withAnimation(.linear(duration: 1)) {
                        camera = .camera(MapCamera(centerCoordinate: here.cl, distance: 2_500))
                    }
                }
            }
        }
        .task {
            camera = .rect(plannedSegment.boundingMapRect(padding: 0.3))
            while !Task.isCancelled {
                store.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .confirmationDialog("End your run early?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End run", role: .destructive) { store.finishRun(completed: false) }
            Button("Keep running", role: .cancel) {}
        } message: {
            Text("You'll keep the distance you've covered, but only earn half the coins.")
        }
    }

    private var plannedSegment: [Coordinate] {
        guard let leg else { return [] }
        return leg.slice(fromKm: run.startProgressKm, toKm: min(run.startProgressKm + run.plannedKm, leg.totalKm))
    }

    // MARK: - Map

    @ViewBuilder
    private func map(now: Date) -> some View {
        if let leg {
            let track = leg.track
            let currentKm = run.startProgressKm + run.distanceKm(at: now)
            let done = leg.slice(fromKm: run.startProgressKm, toKm: currentKm, track: track)
            let ahead = leg.slice(fromKm: currentKm, toKm: run.startProgressKm + run.plannedKm, track: track)
            let here = leg.coordinate(atProgressKm: currentKm, track: track)
            Map(position: $camera) {
                MapPolyline(coordinates: leg.path.clCoordinates)
                    .stroke(.gray.opacity(0.45), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 7]))
                MapPolyline(coordinates: ahead.clCoordinates)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: done.clCoordinates)
                    .stroke(Theme.orange, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                if let start = done.first {
                    Annotation("", coordinate: start.cl) {
                        Circle().fill(.white).frame(width: 12, height: 12).overlay(Circle().stroke(.black, lineWidth: 2))
                    }
                }
                if let finish = ahead.last {
                    Annotation("Finish", coordinate: finish.cl) {
                        Image(systemName: "flag.checkered").font(.title3).padding(6)
                            .background(.white, in: Circle())
                    }
                }
                Annotation("", coordinate: here.cl) { RunnerDot() }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass() }
            .onMapCameraChange(frequency: .onEnd) { ctx in
                _ = ctx // user panning keeps their view; tap "follow" to re-lock.
            }
        } else {
            LinearGradient(colors: [Theme.dusk, Theme.night], startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: - Overlays

    private var header: some View {
        HStack(spacing: 8) {
            if let leg {
                Label("\(leg.from.name) → \(leg.to.name)", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.subheadline.bold())
                    .lineLimit(1)
            }
            Spacer()
            if let host = run.group?.host {
                Label(host == store.state.profile?.name ? "Group run" : "with \(host)", systemImage: "person.3.fill")
                    .font(.caption.bold())
            }
            Button {
                follow.toggle()
                if !follow { camera = .rect(plannedSegment.boundingMapRect(padding: 0.3)) }
            } label: {
                Image(systemName: follow ? "location.fill" : "location")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal)
    }

    private func panel(now: Date) -> some View {
        let fraction = run.fraction(at: now)
        return VStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(Fmt.clock(run.remaining(at: now)))
                    .font(.system(size: 64, weight: .heavy, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                Text("of focus left").font(.subheadline).foregroundStyle(.secondary)
            }
            LegProgressBar(fraction: fraction)
            HStack {
                StatTile(label: "Distance", value: Fmt.km(run.distanceKm(at: now)), unit: "/ \(Fmt.km(run.plannedKm, digits: 1)) km")
                StatTile(label: "Pace", value: Fmt.pace(run.paceSecPerKm), unit: "/km")
                StatTile(label: "Elapsed", value: Fmt.clock(max(0, now.timeIntervalSince(run.startDate)).rounded(.down)))
            }
            if store.state.profile?.strictMode == true {
                Label("Strict mode: leaving Roam for over a minute ends your run.", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
            } else if run.distractions > 0 {
                Label("Left the app \(run.distractions)×. Stay focused!", systemImage: "eye.slash")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                confirmEnd = true
            } label: {
                Text(fraction >= 1 ? "Finishing…" : "End run").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
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
                    .pickerStyle(.segmented)
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
    @State private var showDestinations = false

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
                VStack(spacing: 6) {
                    Text(isHost ? "Your group run" : "\(invite.host)'s group run").font(.title.bold())
                    Text("\(invite.title) · \(Fmt.duration(invite.duration)) of focus")
                        .foregroundStyle(.secondary)
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
                if now >= invite.start, now < invite.end, store.state.currentLeg != nil {
                    store.startGroupRun(invite)
                }
            }
        }
        .sheet(isPresented: $showDestinations) { DestinationPicker() }
    }

    @ViewBuilder
    private func status(now: Date) -> some View {
        if now >= invite.end {
            Label("This run already finished.", systemImage: "flag.checkered").font(.headline)
        } else if store.state.currentLeg == nil {
            VStack(spacing: 10) {
                Text("Pick a destination so your runner knows where to go.").multilineTextAlignment(.center)
                Button("Choose destination") { showDestinations = true }
                    .buttonStyle(.borderedProminent)
            }
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
