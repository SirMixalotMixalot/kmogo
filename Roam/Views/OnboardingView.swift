import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var homeID = Cities.waterloo.id
    @State private var pace = 360

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        RunnerDot(size: 56)
                        Text("Roam").font(.system(size: 44, weight: .heavy, design: .rounded))
                        Text("Study to run across the world. Every focus session is a run on a real map — a 30 minute session is a 5K. Keep studying and watch yourself travel from city to city.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section("What should we call you?") {
                    TextField("Your name", text: $name)
                        .textContentType(.givenName)
                }

                Section {
                    Picker("Start in", selection: $homeID) {
                        ForEach(Cities.all) { city in
                            Text("\(city.emoji) \(city.name)").tag(city.id)
                        }
                    }
                } header: {
                    Text("Starting city")
                } footer: {
                    Text("This is where your journey begins.")
                }

                Section {
                    PacePicker(pace: $pace)
                } header: {
                    Text("Your pace")
                } footer: {
                    Text("At \(Fmt.pace(pace)) /km, a 5K is a \(Fmt.duration(5 * Double(pace))) study session.")
                }

                Section {
                    Button {
                        let home = Cities.city(id: homeID) ?? Cities.waterloo
                        store.completeOnboarding(name: name, home: home, pace: pace)
                        Task { await Notifier.requestAuthorization() }
                    } label: {
                        Text("Start roaming").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                }
            }
        }
    }
}

struct PacePicker: View {
    @Binding var pace: Int

    var body: some View {
        Stepper(value: $pace, in: 240...540, step: 15) {
            HStack {
                Text("Pace")
                Spacer()
                Text("\(Fmt.pace(pace)) /km").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

struct DestinationPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var origin: City? { store.state.currentCity }

    private var options: [City] {
        guard let origin else { return [] }
        return Cities.all
            .filter { $0.id != origin.id }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.region.localizedCaseInsensitiveContains(query) }
            .sorted { Geo.distanceKm(origin.coordinate, $0.coordinate) < Geo.distanceKm(origin.coordinate, $1.coordinate) }
    }

    var body: some View {
        NavigationStack {
            List(options) { city in
                Button {
                    Task {
                        await store.setDestination(city)
                        dismiss()
                    }
                } label: {
                    row(city)
                }
                .disabled(store.isRouting)
            }
            .searchable(text: $query, prompt: "Search cities")
            .navigationTitle("Where to?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .overlay {
                if store.isRouting {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Plotting your route…").font(.headline)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private func row(_ city: City) -> some View {
        let km = origin.map { Cities.estimatedKm(from: $0, to: city) } ?? 0
        let visited = store.state.cities.contains { $0.city.id == city.id }
        return HStack(spacing: 12) {
            Text(city.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(city.name).font(.headline).foregroundStyle(.primary)
                    if visited { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.caption) }
                }
                Text(city.region).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("~\(Int(km)) km").font(.subheadline.monospacedDigit()).foregroundStyle(.primary)
                Text("~\(Fmt.duration(store.durationFor(km: km))) of study").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
