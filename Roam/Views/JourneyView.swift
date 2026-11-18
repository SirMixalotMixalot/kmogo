import SwiftUI
import MapKit

struct JourneyView: View {
    @Environment(AppStore.self) private var store
    @State private var showDestinations = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                worldMap.ignoresSafeArea(edges: .top)
                summary
            }
            .navigationTitle("Journey")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showDestinations) { DestinationPicker() }
        }
    }

    private var worldMap: some View {
        Map(initialPosition: .automatic, interactionModes: .all) {
            // Everywhere you've actually been: runs (solid) and ticket rides (dashed).
            ForEach(store.state.runs) { run in
                MapPolyline(coordinates: run.path.clCoordinates)
                    .stroke(Theme.orange.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            ForEach(store.state.transits) { ride in
                MapPolyline(coordinates: ride.path.clCoordinates)
                    .stroke(.purple.opacity(0.8), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6]))
            }
            if let leg = store.state.currentLeg {
                let track = leg.track
                MapPolyline(coordinates: leg.path.clCoordinates)
                    .stroke(.gray, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 6]))
                MapPolyline(coordinates: leg.slice(fromKm: 0, toKm: leg.progressKm, track: track).clCoordinates)
                    .stroke(Theme.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                Marker(leg.to.name, systemImage: "flag.checkered", coordinate: leg.to.coordinate.cl).tint(.gray)
            }
            ForEach(store.state.cities) { collected in
                Annotation(collected.city.name, coordinate: collected.city.coordinate.cl) {
                    Text(collected.city.emoji)
                        .font(.title3)
                        .padding(5)
                        .background(.white, in: Circle())
                        .overlay(Circle().stroke(Theme.orange, lineWidth: 2))
                }
            }
            Annotation("You", coordinate: store.currentCoordinate.cl) { RunnerDot(size: 30) }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .id(store.state.currentLeg?.id) // re-fit the camera when the leg changes
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StatTile(label: "Run", value: Fmt.km(store.totalKm, digits: 1), unit: "km")
                StatTile(label: "Studied", value: Fmt.duration(store.totalStudyTime))
                StatTile(label: "Cities", value: "\(store.state.cities.count)")
            }
            Divider()
            if let leg = store.state.currentLeg {
                HStack {
                    Text("Heading to \(leg.to.emoji) \(leg.to.name)").font(.headline)
                    Spacer()
                    Button("Change") { showDestinations = true }.font(.subheadline)
                }
                LegProgressBar(fraction: leg.fraction)
                Text("\(Fmt.km(leg.remainingKm, digits: 1)) km to go · \(leg.mode.label)")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let city = store.state.currentCity {
                HStack {
                    Text("Resting in \(city.emoji) \(city.name)").font(.headline)
                    Spacer()
                    Button("Next stop") { showDestinations = true }.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .padding()
    }
}
