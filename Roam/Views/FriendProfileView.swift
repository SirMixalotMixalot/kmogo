import SwiftUI

struct ProfileAvatar: View {
    let name: String
    var size: CGFloat = 48

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.orange)
            .frame(width: size, height: size)
            .background(Theme.orange.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

struct UsernameEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var failure: String?

    private var normalized: String { RoamUsername.normalized(username) }
    private var canSave: Bool {
        RoamUsername.isValid(normalized) && normalized != account.profile?.username && !account.isBusy
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("@").foregroundStyle(.secondary)
                        TextField("Username", text: $username)
                            .textContentType(.nickname)
                            .keyboardType(.asciiCapable)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { if canSave { Task { await save() } } }
                    }
                } footer: {
                    Text("Use 3–20 letters, numbers, or underscores. Start with a letter or number. People can find you by this username. Changing it also changes your profile link.")
                }
                if let failure { Section { Text(failure).foregroundStyle(.red) } }
                if account.isBusy { ProgressView().frame(maxWidth: .infinity) }
            }
            .navigationTitle("Your username")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(account.isBusy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(account.isBusy)
            .onAppear { username = account.profile?.username ?? "" }
            .onChange(of: username) { _, _ in failure = nil }
        }
    }

    private func save() async {
        guard canSave else { return }
        if await account.setUsername(normalized, store: store) { dismiss() }
        else { failure = account.errorMessage }
    }
}

struct FriendSearchView: View {
    @Environment(AccountStore.self) private var account
    @State private var search = ""
    @State private var results: [RoamPublicProfile] = []
    @State private var loading = false
    @State private var failure: String?
    private var query: String { RoamUsername.normalized(search) }

    var body: some View {
        List {
            if account.session == nil {
                ContentUnavailableView("Sign in to find friends", systemImage: "person.crop.circle")
                NavigationLink("Sign in or create an account") { AccountView() }
            } else if !RoamUsername.canSearch(query) {
                ContentUnavailableView("Find your people", systemImage: "person.2",
                    description: Text("Enter at least 2 letters of a username. You can also open a friend’s profile link."))
            } else if loading {
                ProgressView("Searching…").frame(maxWidth: .infinity)
            } else if let failure {
                ContentUnavailableView("Couldn’t search", systemImage: "wifi.exclamationmark", description: Text(failure))
                Button("Try again") { Task { await find() } }
            } else if results.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                ForEach(results) { profile in
                    NavigationLink { FriendProfileView(username: profile.username) } label: {
                        HStack(spacing: 12) {
                            ProfileAvatar(name: profile.displayName)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.displayName).font(.headline)
                                Text("@\(profile.username)").foregroundStyle(.secondary)
                            }
                            Spacer()
                            if profile.relationship == .accepted {
                                Image(systemName: "person.crop.circle.badge.checkmark").foregroundStyle(.green)
                                    .accessibilityLabel("Friends")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Find friends")
        .searchable(text: $search, prompt: "Search usernames")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .task(id: query) { await find() }
    }

    private func find() async {
        let requestedQuery = query
        results = []
        failure = nil
        guard account.session != nil, RoamUsername.canSearch(requestedQuery) else { loading = false; return }
        loading = true
        do {
            try await Task.sleep(for: .milliseconds(300))
            let found = try await account.searchProfiles(requestedQuery)
            guard !Task.isCancelled, requestedQuery == query else { return }
            results = found
            loading = false
        } catch {
            guard !Task.isCancelled, requestedQuery == query else { return }
            failure = AccountMessages.message(for: error)
            loading = false
        }
    }
}

struct FriendProfileView: View {
    let username: String
    @Environment(AppStore.self) private var store
    @Environment(AccountStore.self) private var account
    @State private var profile: RoamPublicProfile?
    @State private var loading = true
    @State private var failure: String?
    @State private var actionFailure: String?
    @State private var confirmRemoval = false
    @State private var showUsernameEditor = false

    var body: some View {
        List {
            if account.session == nil {
                ContentUnavailableView("Meet @\(username)", systemImage: "person.crop.circle",
                    description: Text("Sign in to view this profile and add them as a friend."))
                NavigationLink("Sign in or create an account") { AccountView() }
            } else if loading {
                ProgressView("Loading profile…").frame(maxWidth: .infinity)
            } else if let failure {
                ContentUnavailableView("Couldn’t load profile", systemImage: "wifi.exclamationmark", description: Text(failure))
                Button("Try again") { Task { await load() } }
            } else if let profile {
                Section {
                    VStack(spacing: 10) {
                        ProfileAvatar(name: profile.displayName, size: 80)
                        Text(profile.displayName).font(.title2.bold())
                        Text("@\(profile.username)").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical)
                    relationshipActions(profile)
                    if let link = profile.link { ShareLink("Share profile", item: link.url) }
                }
                if profile.relationship == .accepted {
                    Section("Shared journey") {
                        if let seconds = profile.studySeconds, let km = profile.virtualKm {
                            LabeledContent("Studied", value: Fmt.duration(Double(seconds)))
                            LabeledContent("Virtual distance", value: "\(Fmt.km(km, digits: 1)) km")
                        } else {
                            Text("Progress isn’t shared yet.").foregroundStyle(.secondary)
                        }
                    }
                }
                if let actionFailure { Section { Text(actionFailure).foregroundStyle(.red) } }
                if account.isBusy { ProgressView().frame(maxWidth: .infinity) }
            } else {
                ContentUnavailableView("User not found", systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("This username may have changed. Ask your friend for their latest profile link."))
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: account.session?.user.id) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showUsernameEditor, onDismiss: { Task { await load() } }) { UsernameEditorView() }
        .confirmationDialog("Remove this friend or request?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            if let id = profile?.friendshipID {
                Button("Remove", role: .destructive) {
                    Task { await act { await account.removeFriendship(id, store: store) } }
                }
            }
        }
    }

    @ViewBuilder
    private func relationshipActions(_ profile: RoamPublicProfile) -> some View {
        switch profile.relationship {
        case .ownProfile:
            Text("This is your profile.").foregroundStyle(.secondary)
            Button("Edit username") { showUsernameEditor = true }
        case .none:
            Button {
                Task { await act { await account.requestFriend(username: profile.username, store: store) } }
            } label: { Label("Add friend", systemImage: "person.badge.plus") }
            .disabled(account.isBusy)
        case .incoming:
            Text("Sent you a friend request").foregroundStyle(.secondary)
            if let id = profile.friendshipID {
                Button("Accept request") { Task { await act { await account.acceptFriendship(id, store: store) } } }
                    .disabled(account.isBusy)
                Button("Decline request", role: .destructive) { confirmRemoval = true }.disabled(account.isBusy)
            }
        case .outgoing:
            Label("Request sent", systemImage: "clock").foregroundStyle(.secondary)
            Button("Cancel request", role: .destructive) { confirmRemoval = true }.disabled(account.isBusy)
        case .accepted:
            Label("Friends", systemImage: "person.crop.circle.badge.checkmark").foregroundStyle(.green)
            Button("Remove friend", role: .destructive) { confirmRemoval = true }.disabled(account.isBusy)
        }
    }

    private func load() async {
        guard account.session != nil else { loading = false; return }
        loading = true
        failure = nil
        do {
            let result = try await account.publicProfile(username: username)
            guard !Task.isCancelled else { return }
            profile = result
            loading = false
        } catch {
            guard !Task.isCancelled else { return }
            failure = AccountMessages.message(for: error)
            loading = false
        }
    }

    private func act(_ operation: () async -> Bool) async {
        actionFailure = nil
        if await operation() { await load() }
        else { actionFailure = account.errorMessage ?? "Couldn’t update this friend request. Try again." }
    }
}
