import SwiftUI

struct PassportView: View {
    @Environment(AppStore.self) private var store
    @State private var selected: RunRecord?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section { profileHeader }

                Section("Cities collected · \(store.state.cities.count)/\(Cities.all.count)") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                        ForEach(Cities.all) { city in
                            let got = store.state.cities.contains { $0.city.id == city.id }
                            VStack(spacing: 4) {
                                Text(got ? city.emoji : "🔒").font(.title)
                                    .grayscale(got ? 0 : 1).opacity(got ? 1 : 0.35)
                                Text(city.name).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
                                    .foregroundStyle(got ? .primary : .secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }

                if !store.state.places.isEmpty {
                    Section("Places passed through") {
                        ForEach(store.state.places.reversed()) { place in
                            HStack {
                                Label(place.name, systemImage: "mappin.circle.fill")
                                Spacer()
                                Text(place.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Runs") {
                    if store.state.runs.isEmpty {
                        Text("No runs yet. Your first 5K is 30 minutes away.").foregroundStyle(.secondary)
                    }
                    ForEach(store.state.runs) { run in
                        Button { selected = run } label: { runRow(run) }
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Passport")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(item: $selected) { run in
                RunSummaryView(record: store.run(id: run.id) ?? run, isNew: false) { selected = nil }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RunnerDot(size: 48)
                VStack(alignment: .leading) {
                    Text(store.state.profile?.name ?? "Runner").font(.title2.bold())
                    Text("Pace \(Fmt.pace(store.pace)) /km").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                CoinBadge(coins: store.state.coins)
            }
            HStack {
                StatTile(label: "Total", value: Fmt.km(store.totalKm, digits: 1), unit: "km")
                StatTile(label: "Studied", value: Fmt.duration(store.totalStudyTime))
                StatTile(label: "Longest", value: store.longestRun.map { Fmt.duration($0.duration) } ?? "—")
            }
        }
        .padding(.vertical, 6)
    }

    private func runRow(_ run: RunRecord) -> some View {
        HStack(spacing: 12) {
            RouteShape(points: run.path)
                .stroke(Theme.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(width: 44, height: 44)
                .padding(4)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(Fmt.km(run.distanceKm)) km").font(.headline)
                    if run.isGroup { Image(systemName: "person.3.fill").font(.caption) }
                    if !run.completed { Text("DNF").font(.caption2.bold()).foregroundStyle(.red) }
                }
                Text(run.routeLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.duration(run.duration)).font(.subheadline.monospacedDigit())
                Text(run.startDate.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: Binding(
                        get: { store.state.profile?.name ?? "" },
                        set: { v in store.updateProfile { $0.name = v } }))
                    PacePicker(pace: Binding(
                        get: { store.pace },
                        set: { v in store.updateProfile { $0.paceSecPerKm = v } }))
                }
                Section {
                    Toggle("Strict mode", isOn: Binding(
                        get: { store.state.profile?.strictMode ?? false },
                        set: { v in store.updateProfile { $0.strictMode = v } }))
                } footer: {
                    Text("If you leave Roam for more than a minute during a run, your runner stops and the run ends.")
                }
                Section {
                    Button("Reset all progress", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Reset everything?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) {
                    store.resetProgress()
                    dismiss()
                }
            } message: {
                Text("Your runs, cities, and coins will be erased.")
            }
        }
    }
}
