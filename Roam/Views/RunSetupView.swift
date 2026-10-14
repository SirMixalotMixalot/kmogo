import SwiftUI
import MapKit

struct RunSetupView: View {
    @Environment(AppStore.self) private var store
    @State private var preset: RunPreset = .fiveK
    @State private var customMinutes: Double = 60
    @State private var showDestinations = false
    @State private var showGroup = false
    @State private var pendingInvite: GroupInvite?

    private var km: Double {
        preset.km ?? customMinutes * 60 / Double(store.pace)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    locationCard
                    if store.state.currentLeg != nil {
                        presetPicker
                        startButtons
                    }
                }
                .padding()
            }
            .navigationTitle("Roam")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { CoinBadge(coins: store.state.coins) }
            }
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

    // MARK: - Location

    @ViewBuilder private var locationCard: some View {
        if let leg = store.state.currentLeg {
            VStack(alignment: .leading, spacing: 12) {
                LegMiniMap(leg: leg)
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .allowsHitTesting(false)
                HStack {
                    Text("\(leg.from.emoji) \(leg.from.name)").font(.subheadline.bold())
                    Spacer()
                    Text("\(leg.to.name) \(leg.to.emoji)").font(.subheadline.bold())
                }
                LegProgressBar(fraction: leg.fraction)
                HStack {
                    Text("\(Fmt.km(leg.progressKm, digits: 1)) of \(Fmt.km(leg.totalKm, digits: 1)) km")
                    Spacer()
                    Text("\(Fmt.duration(store.durationFor(km: leg.remainingKm))) of study to go")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
        } else if let city = store.state.currentCity {
            VStack(alignment: .leading, spacing: 12) {
                Text(city.emoji).font(.system(size: 48))
                Text("You're in \(city.name)").font(.title2.bold())
                Text(store.state.bankedKm > 0.05
                     ? "You've got \(Fmt.km(store.state.bankedKm, digits: 1)) km banked from your last run. Pick your next destination to keep roaming."
                     : "Pick your next destination. Every minute you study moves you closer.")
                    .foregroundStyle(.secondary)
                Button {
                    showDestinations = true
                } label: {
                    Label("Choose destination", systemImage: "mappin.and.ellipse")
                        .font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Presets

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose your run").font(.title3.bold())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(RunPreset.allCases) { p in
                    PresetCard(preset: p, selected: p == preset,
                               subtitle: p.km.map { Fmt.duration(store.durationFor(km: $0)) } ?? "Pick a time")
                        .onTapGesture { preset = p }
                }
            }
            if preset == .custom {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Study for \(Fmt.duration(customMinutes * 60))").font(.headline)
                        Spacer()
                        Text("\(Fmt.km(km, digits: 1)) km").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $customMinutes, in: 10...600, step: 5)
                    Text(customMinutes >= 240 ? "Ultramarathon mode. Legendary. 🔥" : "Slide up to 10 hours for an ultra.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var startButtons: some View {
        VStack(spacing: 10) {
            Button {
                store.startRun(km: km)
            } label: {
                VStack(spacing: 2) {
                    Text("Start run").font(.headline)
                    Text("\(Fmt.km(km, digits: 1)) km · \(Fmt.duration(store.durationFor(km: km))) of focus")
                        .font(.caption).opacity(0.85)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

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

struct PresetCard: View {
    let preset: RunPreset
    let selected: Bool
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(preset.title).font(.title2.weight(.heavy))
            Text(subtitle).font(.subheadline).foregroundStyle(selected ? .white.opacity(0.9) : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .foregroundStyle(selected ? .white : .primary)
        .background(selected ? AnyShapeStyle(Theme.orange) : AnyShapeStyle(.background.secondary),
                    in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
    }
}

/// Non-interactive map of a leg with the runner's position.
struct LegMiniMap: View {
    let leg: Leg

    var body: some View {
        let track = leg.track
        let done = leg.slice(fromKm: 0, toKm: leg.progressKm, track: track)
        let here = leg.coordinate(atProgressKm: leg.progressKm, track: track)
        Map(initialPosition: .rect(leg.path.boundingMapRect(padding: 0.15))) {
            MapPolyline(coordinates: leg.path.clCoordinates)
                .stroke(.gray.opacity(0.6), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 6]))
            MapPolyline(coordinates: done.clCoordinates)
                .stroke(Theme.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            Marker(leg.to.name, coordinate: leg.to.coordinate.cl).tint(.green)
            Annotation("", coordinate: here.cl) { RunnerDot(size: 26) }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}
