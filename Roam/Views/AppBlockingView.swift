import SwiftUI
import FamilyControls

@MainActor
struct AppBlockingView: View {
    @Environment(AppStore.self) private var store
    @State private var blocker = AppBlocker.shared
    @State private var showPicker = false
    @State private var showDemoPermission = false

    var body: some View {
        @Bindable var blocker = blocker
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Block distracting apps", isOn: Binding(
                get: { blocker.enabled && blocker.authorized },
                set: { enabled in
                    if !enabled { blocker.enabled = false; blocker.stop() }
                    else {
                        #if targetEnvironment(simulator)
                        if blocker.authorized { blocker.enabled = true; showPicker = true }
                        else { showDemoPermission = true }
                        #else
                        Task {
                            if await blocker.authorize() {
                                blocker.enabled = true
                                showPicker = true
                            }
                        }
                        #endif
                    }
                }))
                .disabled(blocker.requesting || store.state.activeRun != nil)
            if blocker.enabled && blocker.authorized {
                Button { showPicker = true } label: {
                    Label(blocker.hasSelection ? "Change blocked apps" : "Choose apps to block", systemImage: "hand.raised.fill")
                }
                .disabled(store.state.activeRun != nil)
                #if targetEnvironment(simulator)
                Text("\(blocker.demoApps.count) sample apps selected")
                    .font(.caption).foregroundStyle(.secondary)
                #else
                Text("\(blocker.selection.applicationTokens.count) apps · \(blocker.selection.categoryTokens.count) categories · \(blocker.selection.webDomainTokens.count) websites selected")
                    .font(.caption).foregroundStyle(.secondary)
                #endif
            }
            if AppBlocker.isSimulatorDemo {
                Label("Simulator demo · no apps are actually blocked", systemImage: "testtube.2")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Selected apps are blocked during runs and unlock when the timer ends or you end the run. Screen Time permission is required.")
                .font(.caption).foregroundStyle(.secondary)
        }
        #if targetEnvironment(simulator)
        .alert("Allow demo Screen Time access?", isPresented: $showDemoPermission) {
            Button("Not now", role: .cancel) {}
            Button("Allow demo access") {
                blocker.demoAuthorized = true
                blocker.enabled = true
                showPicker = true
            }
        } message: {
            Text("This previews Roam’s setup flow in the simulator. It does not grant Apple Screen Time permission or block real apps.")
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                List {
                    Section {
                        ForEach(["Instagram", "TikTok", "YouTube", "Reddit", "Safari"], id: \.self) { name in
                            Toggle(name, isOn: Binding(
                                get: { blocker.demoApps.contains(name) },
                                set: { selected in
                                    if selected { blocker.demoApps.insert(name) }
                                    else { blocker.demoApps.remove(name) }
                                }))
                        }
                    } header: { Text("Sample apps") } footer: {
                        Text("Demo selections only. These do not represent apps installed on this simulator.")
                    }
                }
                .navigationTitle("Demo blocked apps")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { showPicker = false } }
                }
            }
        }
        #else
        .familyActivityPicker(isPresented: $showPicker, selection: $blocker.selection)
        #endif
    }
}
