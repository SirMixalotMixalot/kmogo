import SwiftUI
import MapKit

struct FriendsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AccountStore.self) private var account
    @State private var inviteCode = ""
    @State private var selectedFriend: RoamFriend?
    @State private var confirmRemoval = false

    private var requests: [RoamFriend] { account.friends.filter { $0.status != .accepted } }
    private var accepted: [RoamFriend] { account.friends.filter { $0.status == .accepted } }
    private var visibleFriends: [RoamFriend] { accepted.filter { $0.coordinate != nil } }

    var body: some View {
        NavigationStack {
            List {
                if account.session == nil {
                    Section {
                        ContentUnavailableView("Study with friends", systemImage: "person.2",
                            description: Text("Sign in to exchange friend codes and share your virtual journey."))
                        NavigationLink("Sign in or create an account") { AccountView() }
                    }
                } else {
                    if let profile = account.profile {
                        Section {
                            Text(profile.inviteCode.uuidString.lowercased())
                                .font(.footnote.monospaced()).textSelection(.enabled)
                            ShareLink("Share friend code", item: profile.inviteCode.uuidString.lowercased())
                            Toggle("Share progress with accepted friends", isOn: Binding(
                                get: { account.profile?.shareProgress ?? false },
                                set: { enabled in Task { await account.setSharing(enabled, store: store) } }
                            ))
                            .disabled(account.isBusy)
                        } header: {
                            Text("Your friend code")
                        } footer: {
                            Text("Shares your virtual map position, study time, and virtual distance. Updates while Roam is open.")
                        }
                    }
                    Section("Add a friend") {
                        TextField("Paste a friend code", text: $inviteCode)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Send request") {
                            Task {
                                await account.requestFriend(code: inviteCode, store: store)
                                if account.errorMessage == nil { inviteCode = "" }
                            }
                        }
                        .disabled(inviteCode.isEmpty || account.isBusy || account.profile == nil)
                    }
                    if !visibleFriends.isEmpty {
                        Section("Virtual positions") {
                            Map(initialPosition: .automatic) {
                                ForEach(visibleFriends) { friend in
                                    if let coordinate = friend.coordinate {
                                        Marker(friend.displayName, systemImage: "person.fill", coordinate: coordinate.cl)
                                            .tint(Theme.orange)
                                    }
                                }
                            }
                            .frame(height: 250)
                            .listRowInsets(EdgeInsets())
                        }
                    }
                    if !requests.isEmpty {
                        Section("Requests") {
                            ForEach(requests) { friend in friendRow(friend) }
                        }
                    }
                    Section("Friends") {
                        if accepted.isEmpty {
                            Text("Exchange a friend code to start studying together.").foregroundStyle(.secondary)
                        }
                        ForEach(accepted) { friend in friendRow(friend) }
                    }
                    AccountFeedback()
                }
            }
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { AccountView() } label: {
                        Label("Account", systemImage: "person.crop.circle")
                    }
                }
            }
            .refreshable { await account.refresh(store: store) }
            .task { await account.refresh(store: store) }
            .confirmationDialog("Remove this friend or request?", isPresented: $confirmRemoval,
                                titleVisibility: .visible) {
                if let friend = selectedFriend {
                    Button("Remove \(friend.displayName)", role: .destructive) {
                        Task { await account.remove(friend, store: store) }
                    }
                }
            }
        }
    }

    private func friendRow(_ friend: RoamFriend) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(friend.displayName).font(.headline)
                switch friend.status {
                case .incoming:
                    Text("Wants to add you").font(.caption).foregroundStyle(.secondary)
                case .outgoing:
                    Text("Request sent").font(.caption).foregroundStyle(.secondary)
                case .accepted:
                    if let seconds = friend.studySeconds, let km = friend.virtualKm {
                        Text("\(Fmt.duration(Double(seconds))) studied · \(Fmt.km(km, digits: 1)) virtual km")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Progress is private").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if friend.status == .incoming {
                Button("Accept") { Task { await account.accept(friend, store: store) } }
                    .buttonStyle(.bordered)
            }
            Menu {
                Button("Remove", role: .destructive) {
                    selectedFriend = friend
                    confirmRemoval = true
                }
            } label: {
                Label("Friend options", systemImage: "ellipsis")
                    .labelStyle(.iconOnly).padding(8)
            }
        }
        .disabled(account.isBusy)
    }
}
