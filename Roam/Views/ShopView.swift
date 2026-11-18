import SwiftUI

struct ShopView: View {
    @Environment(AppStore.self) private var store
    @State private var confirm: Transit?
    @State private var arrived: City?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Earn coins by running — 10 per km, plus a 20% bonus when you finish a run without bailing.")
                        Text("Spend them on tickets to cover ground faster.")
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                }

                Section("Tickets") {
                    ForEach(Transit.allCases) { item in
                        ticketRow(item)
                    }
                }

                if !store.state.transits.isEmpty {
                    Section("Recent rides") {
                        ForEach(store.state.transits.prefix(10)) { ride in
                            HStack {
                                Image(systemName: ride.kind.symbol).frame(width: 28)
                                VStack(alignment: .leading) {
                                    Text("\(Fmt.km(ride.km, digits: 1)) km by \(ride.kind.rawValue)")
                                    Text("\(ride.legFrom) → \(ride.legTo)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(ride.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Shop")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { CoinBadge(coins: store.state.coins) } }
            .alert(confirm.map { "Buy a \($0.name.lowercased())?" } ?? "",
                   isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                   presenting: confirm) { item in
                Button("Buy for \(item.price) coins") {
                    store.buy(item)
                    if let city = store.arrivedCity {
                        arrived = city
                        store.arrivedCity = nil
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { item in
                Text(item.blurb)
            }
            .alert(arrived.map { "\($0.emoji) Welcome to \($0.name)!" } ?? "",
                   isPresented: Binding(get: { arrived != nil }, set: { if !$0 { arrived = nil } })) {
                Button("Nice") {}
            } message: {
                Text("You've added a new city to your passport. Pick your next destination from the Run tab.")
            }
        }
    }

    private func ticketRow(_ item: Transit) -> some View {
        let leg = store.state.currentLeg
        let skip = leg.map { min(item.km ?? $0.remainingKm, $0.remainingKm) }
        return HStack(spacing: 14) {
            Image(systemName: item.symbol)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Theme.orange.gradient, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.headline)
                Text(item.blurb).font(.caption).foregroundStyle(.secondary)
                if let skip, let leg {
                    Text("Saves \(Fmt.duration(store.durationFor(km: skip))) on the way to \(leg.to.name)")
                        .font(.caption2).foregroundStyle(Theme.orange)
                }
            }
            Spacer()
            Button {
                confirm = item
            } label: {
                Text("\(item.price)").monospacedDigit()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.canBuy(item))
        }
        .padding(.vertical, 4)
    }
}
