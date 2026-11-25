import SwiftUI

@main
struct RoamApp: App {
    @State private var store = AppStore(fileURL: RoamApp.isTesting ? nil : AppStore.defaultURL,
                                        notificationsEnabled: !RoamApp.isTesting)
    @State private var account = AccountStore()

    static var isTesting: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(account)
                .tint(Theme.orange)
        }
    }
}

enum Theme {
    static let orange = Color(red: 1.0, green: 0.42, blue: 0.17)
    static let uiOrange = UIColor(red: 1.0, green: 0.42, blue: 0.17, alpha: 1)
    static let night = Color(red: 0.05, green: 0.06, blue: 0.09)
    static let dusk = Color(red: 0.13, green: 0.10, blue: 0.20)
}

struct RootView: View {
    @State private var blocker = AppBlocker.shared
    @Environment(AppStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.scenePhase) private var scenePhase

    private var showFlow: Binding<Bool> {
        Binding(
            get: { !account.isOpeningRecoveryLink && !account.isRecoveringPassword
                && (store.state.activeRun != nil || store.finishedRunID != nil || store.lobbyInvite != nil) },
            set: { if !$0 { store.finishedRunID = nil; store.lobbyInvite = nil } }
        )
    }

    var body: some View {
        Group {
            if account.isOpeningRecoveryLink {
                ProgressView("Verifying reset link…")
            } else if account.isRecoveringPassword {
                PasswordRecoveryView()
            } else if let message = account.journeyError {
                ContentUnavailableView {
                    Label("Couldn’t open your journey", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await account.retryJourney(store: store) } }
                }
            } else if account.isRestoring && !RoamApp.isTesting {
                ProgressView("Opening Roam…")
            } else if store.state.profile == nil {
                OnboardingView()
            } else {
                MainTabs()
            }
        }
        // Lobby → running → summary all live in one full-screen flow so presentations never collide.
        .fullScreenCover(isPresented: showFlow) {
            RunFlowView().environment(store).tint(Theme.orange)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: store.appDidBackground()
            case .active: store.appDidBecomeActive()
            default: break
            }
        }
        .alert("App blocking", isPresented: Binding(
            get: { blocker.errorMessage != nil },
            set: { if !$0 { blocker.errorMessage = nil } })) {
                Button("OK") { blocker.errorMessage = nil }
            } message: { Text(blocker.errorMessage ?? "") }
        .onOpenURL { url in
            if AccountRecovery.isCallback(url) {
                Task { await account.openPasswordRecovery(url, store: store) }
                return
            }
            guard let invite = GroupInvite(url: url), store.state.activeRun == nil,
                  store.state.profile != nil else { return }
            store.finishedRunID = nil
            store.lobbyInvite = invite
        }
        .alert("Couldn’t open reset link", isPresented: Binding(
            get: { account.recoveryLinkError != nil },
            set: { if !$0 { account.recoveryLinkError = nil } })) {
                Button("OK") { account.recoveryLinkError = nil }
            } message: { Text(account.recoveryLinkError ?? "") }
        .task {
            #if DEBUG
            await store.seedDemoIfRequested()
            #endif
            store.appDidBecomeActive()
            if !RoamApp.isTesting {
                store.appBlocker = .shared
                store.appBlocker?.synchronize(until: store.state.activeRun?.realEndDate)
            }
        }
        .task {
            guard !RoamApp.isTesting else { return }
            await account.observeAuth(store: store)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, !RoamApp.isTesting else { return }
            while !Task.isCancelled {
                await account.refresh(store: store)
                do { try await Task.sleep(for: .seconds(15)) }
                catch { break }
            }
        }
        .onChange(of: store.state.profile?.name) { _, _ in
            Task { await account.refresh(store: store) }
        }
        .onChange(of: store.state.runs.count) { _, _ in
            Task { await account.refresh(store: store) }
        }
    }
}

struct RunFlowView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if let run = store.state.activeRun {
                ActiveRunView(run: run)
            } else if let id = store.finishedRunID, let record = store.run(id: id) {
                RunSummaryView(record: record, arrivedCity: store.arrivedCity, isNew: true) {
                    store.finishedRunID = nil
                    store.arrivedCity = nil
                }
            } else if let invite = store.lobbyInvite {
                LobbyView(invite: invite)
            } else {
                Color.clear
            }
        }
        .animation(.default, value: store.state.activeRun == nil)
    }
}

struct MainTabs: View {
    @State private var tab = MainTabs.initialTab

    /// DEBUG: `-tab N` opens a specific tab (handy for screenshots).
    private static var initialTab: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count else { return 0 }
        return Int(args[i + 1]) ?? 0
    }

    var body: some View {
        TabView(selection: $tab) {
            RunSetupView()
                .tabItem { Label("Run", systemImage: "figure.run") }.tag(0)
            JourneyView()
                .tabItem { Label("Journey", systemImage: "map.fill") }.tag(1)
            ShopView()
                .tabItem { Label("Shop", systemImage: "ticket.fill") }.tag(2)
            PassportView()
                .tabItem { Label("Passport", systemImage: "person.crop.square.filled.and.at.rectangle") }.tag(3)
            FriendsView()
                .tabItem { Label("Friends", systemImage: "person.2.fill") }.tag(4)
        }
    }
}

// MARK: - Shared components

struct CoinBadge: View {
    let coins: Int
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.yellow)
            Text("\(coins)").font(.subheadline.bold().monospacedDigit())
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }
}

struct RunnerDot: View {
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: "figure.run")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.orange, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title3.bold().monospacedDigit())
                if let unit { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LegProgressBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Theme.orange).frame(width: max(8, geo.size.width * fraction))
            }
        }
        .frame(height: 8)
    }
}
