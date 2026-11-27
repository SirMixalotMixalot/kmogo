import SwiftUI
import MapKit

struct FriendsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AccountStore.self) private var account
    @State private var showUsernameEditor = false
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
                            description: Text("Find friends by username and share your virtual journey."))
                        NavigationLink("Sign in or create an account") { AccountView() }
                    }
                } else {
                    if let profile = account.profile {
                        Section {
                            HStack(spacing: 12) {
                                ProfileAvatar(name: profile.displayName)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.displayName).font(.headline)
                                    if let username = profile.username {
                                        Text("@\(username)").foregroundStyle(.secondary)
                                    } else {
                                        Text("Choose a username so friends can find you.")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Button(profile.username == nil ? "Choose a username" : "Edit username") {
                                showUsernameEditor = true
                            }
                            if let username = profile.username, let link = ProfileLink(username: username) {
                                ShareLink("Share your profile", item: link.url)
                            }
                            NavigationLink {
                                FriendSearchView()
                            } label: {
                                Label("Find friends", systemImage: "magnifyingglass")
                            }
                        } header: {
                            Text("Your profile")
                        }
                        Section {
                            Toggle("Share progress with accepted friends", isOn: Binding(
                                get: { account.profile?.shareProgress ?? false },
                                set: { enabled in Task { await account.setSharing(enabled, store: store) } }
                            ))
                            .disabled(account.isBusy)
                        } header: {
                            Text("Progress sharing")
                        } footer: {
                            Text("Shares your virtual map position, study time, and virtual distance. Updates while Roam is open.")
                        }
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
                            Text("Search a username or open a profile link to add your first friend.")
                                .foregroundStyle(.secondary)
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
            .sheet(isPresented: $showUsernameEditor) { UsernameEditorView() }
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
            if let username = friend.username {
                NavigationLink { FriendProfileView(username: username) } label: { friendDetails(friend) }
            } else {
                friendDetails(friend)
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

    private func friendDetails(_ friend: RoamFriend) -> some View {
        HStack(spacing: 12) {
            ProfileAvatar(name: friend.displayName, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(friend.displayName).font(.headline)
                if let username = friend.username {
                    Text("@\(username)").font(.caption).foregroundStyle(.secondary)
                }
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
                        Text("Progress isn’t shared yet").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
