import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class AccountStore {
    private(set) var session: Session?
    private(set) var profile: CloudProfile?
    private(set) var friends: [RoamFriend] = []
    private(set) var isRestoring = true
    private(set) var isBusy = false
    private(set) var isOpeningRecoveryLink = false
    private(set) var isRecoveringPassword = false
    private(set) var passwordUpdated = false
    private(set) var journeyError: String?
    var recoveryLinkError: String?
    var errorMessage: String?
    var notice: String?

    @ObservationIgnored private let client: SupabaseClient
    @ObservationIgnored private var observing = false
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var importGuestProgress = false
    @ObservationIgnored private var lastSnapshot: ProgressSnapshot?

    init(client: SupabaseClient = Backend.client) {
        self.client = client
    }

    func observeAuth(store: AppStore) async {
        guard !observing else { return }
        observing = true
        defer { observing = false }
        for await (event, currentSession) in client.auth.authStateChanges {
            guard !Task.isCancelled else { return }
            do {
                if event == .passwordRecovery, currentSession != nil {
                    isRecoveringPassword = true
                    passwordUpdated = false
                }
                try apply(currentSession, store: store)
                if currentSession != nil { await refresh(store: store) }
            } catch {
                errorMessage = error.localizedDescription
                isRestoring = false
            }
        }
    }

    private func apply(_ nextSession: Session?, store: AppStore) throws {
        if store.accountID != nextSession?.user.id {
            // A session can also expire or be revoked while a run is active.
            if store.state.activeRun != nil { store.finishRun(completed: false) }
            do {
                try store.useAccount(nextSession?.user.id, importGuestProgress: importGuestProgress)
            } catch {
                session = nextSession
                profile = nil
                friends = []
                journeyError = error.localizedDescription
                isRestoring = false
                throw error
            }
            importGuestProgress = false
            profile = nil
            friends = []
            lastSnapshot = nil
        }
        session = nextSession
        if nextSession == nil {
            isRecoveringPassword = false
            passwordUpdated = false
        }
        journeyError = nil
        isRestoring = false
    }

    func retryJourney(store: AppStore) async {
        await perform {
            try apply(session, store: store)
            await refresh(store: store)
        }
    }

    @discardableResult
    func signIn(email: String, password: String, importJourney: Bool, store: AppStore) async -> Bool {
        await perform {
            importGuestProgress = importJourney
            let result = try await client.auth.signIn(email: email, password: password)
            try apply(result, store: store)
            await refresh(store: store)
        }
    }

    @discardableResult
    func signUp(email: String, password: String, name: String, importJourney: Bool, store: AppStore) async -> Bool {
        await perform {
            importGuestProgress = importJourney
            let result = try await client.auth.signUp(
                email: email, password: password, data: ["display_name": .string(cleanName(name))]
            )
            if let resultSession = result.session {
                try apply(resultSession, store: store)
                await refresh(store: store)
            } else {
                importGuestProgress = false
                notice = "Check your email to confirm your account, then return here to sign in."
            }
        }
    }

    func signOut(store: AppStore) async {
        await perform {
            try await client.auth.signOut(scope: .local)
            try apply(nil, store: store)
        }
    }

    @discardableResult
    func requestPasswordReset(email: String) async -> Bool {
        await perform {
            let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { throw AccountError.emailRequired }
            try await client.auth.resetPasswordForEmail(address, redirectTo: AccountRecovery.redirectURL)
            notice = "If an account exists for this email, we sent a reset link. Open it on this iPhone to choose a new password."
        }
    }

    func openPasswordRecovery(_ url: URL, store: AppStore) async {
        guard AccountRecovery.isCallback(url), !isOpeningRecoveryLink else { return }
        isOpeningRecoveryLink = true
        recoveryLinkError = nil
        errorMessage = nil
        notice = nil
        defer { isOpeningRecoveryLink = false }
        do {
            // The SDK exchanges the code with the verifier saved when this device requested the email.
            // A callback URL alone never authorizes a password change.
            let recoveredSession = try await client.auth.session(from: url)
            try apply(recoveredSession, store: store)
            passwordUpdated = false
            isRecoveringPassword = true
        } catch {
            // SDK errors may include the callback URL; don't display codes or tokens in the UI.
            recoveryLinkError = "This reset link could not be verified. It may have expired, already been used, or been requested on another device. Request a new link in Roam and open it on the same iPhone."
        }
    }

    @discardableResult
    func updateRecoveredPassword(_ password: String, confirmation: String) async -> Bool {
        await perform {
            guard isRecoveringPassword, session != nil, !passwordUpdated else {
                throw AccountError.recoveryRequired
            }
            guard password.count >= AccountRecovery.minimumPasswordLength else {
                throw AccountError.passwordTooShort
            }
            guard password == confirmation else { throw AccountError.passwordMismatch }
            try await client.auth.update(user: UserAttributes(password: password))
            passwordUpdated = true
        }
    }

    func finishPasswordRecovery() {
        guard passwordUpdated else { return }
        isRecoveringPassword = false
        passwordUpdated = false
    }

    func refresh(store: AppStore) async {
        guard !refreshing, let user = session?.user, store.accountID == user.id else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            var rows: [CloudProfile] = try await client.from("roam_profiles")
                .select().eq("user_id", value: user.id.uuidString).execute().value
            if rows.isEmpty {
                let name = user.userMetadata["display_name"]?.stringValue
                    ?? store.state.profile?.name ?? "Runner"
                // Concurrent first sign-ins retain the existing profile and sharing choice.
                try await client.from("roam_profiles").upsert(
                    ["user_id": user.id.uuidString, "display_name": cleanName(name)],
                    onConflict: "user_id", ignoreDuplicates: true
                ).execute()
                rows = try await client.from("roam_profiles")
                    .select().eq("user_id", value: user.id.uuidString).execute().value
            }
            guard session?.user.id == user.id else { return }
            guard let row = rows.first else { throw AccountError.profileUnavailable }
            profile = row

            if let localProfile = store.state.profile, cleanName(localProfile.name) != profile?.displayName {
                let updated: CloudProfile = try await client.from("roam_profiles")
                    .update(["display_name": cleanName(localProfile.name)])
                    .eq("user_id", value: user.id.uuidString).select().single().execute().value
                guard session?.user.id == user.id else { return }
                profile = updated
            }

            // Publish the current device's virtual journey. Whole-journey sync is separate.
            if store.state.profile != nil {
                let snapshot = store.progressSnapshot(userID: user.id, at: .now)
                if snapshot != lastSnapshot {
                    try await client.from("roam_progress").upsert(snapshot, onConflict: "user_id").execute()
                    guard session?.user.id == user.id else { return }
                    lastSnapshot = snapshot
                }
            } else if lastSnapshot != nil {
                try await client.from("roam_progress").delete()
                    .eq("user_id", value: user.id.uuidString).execute()
                guard session?.user.id == user.id else { return }
                lastSnapshot = nil
            }

            let updatedFriends: [RoamFriend] = try await client.rpc("roam_list_friends").execute().value
            guard session?.user.id == user.id else { return }
            friends = updatedFriends.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard session?.user.id == user.id else { return }
            errorMessage = error.localizedDescription
        }
    }

    func setSharing(_ enabled: Bool, store: AppStore) async {
        await perform {
            guard let userID = session?.user.id else { return }
            let updated: CloudProfile = try await client.from("roam_profiles")
                .update(["share_progress": enabled]).eq("user_id", value: userID.uuidString)
                .select().single().execute().value
            guard session?.user.id == userID else { return }
            profile = updated
            await refresh(store: store)
        }
    }

    func requestFriend(code: String, store: AppStore) async {
        await perform {
            guard let inviteCode = UUID(uuidString: code.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw AccountError.invalidInvite
            }
            try await client.rpc("roam_request_friend", params: ["p_invite_code": inviteCode.uuidString]).execute()
            notice = "Friend request sent."
            await refresh(store: store)
        }
    }

    func accept(_ friend: RoamFriend, store: AppStore) async {
        await perform {
            let accepted: Bool = try await client.rpc(
                "roam_accept_friend", params: ["p_friendship_id": friend.id.uuidString]
            ).execute().value
            guard accepted else { throw AccountError.requestChanged }
            await refresh(store: store)
        }
    }

    func remove(_ friend: RoamFriend, store: AppStore) async {
        await perform {
            let removed: Bool = try await client.rpc(
                "roam_remove_friend", params: ["p_friendship_id": friend.id.uuidString]
            ).execute().value
            guard removed else { throw AccountError.requestChanged }
            friends.removeAll { $0.id == friend.id }
            await refresh(store: store)
        }
    }

    @discardableResult
    private func perform(_ action: () async throws -> Void) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        errorMessage = nil
        notice = nil
        defer { isBusy = false }
        do {
            try await action()
            return true
        } catch {
            importGuestProgress = false
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? "Runner" : trimmed).prefix(40))
    }

    private enum AccountError: LocalizedError {
        case profileUnavailable, invalidInvite, requestChanged
        case emailRequired, recoveryRequired, passwordTooShort, passwordMismatch

        var errorDescription: String? {
            switch self {
            case .profileUnavailable: "Your profile could not be loaded. Pull down to try again."
            case .invalidInvite: "Paste the full friend code shared by your friend."
            case .requestChanged: "This friend request has changed. Pull down to refresh."
            case .emailRequired: "Enter your account’s email address."
            case .recoveryRequired: "Open a valid password reset link before choosing a new password."
            case .passwordTooShort: "Use at least \(AccountRecovery.minimumPasswordLength) characters for your password."
            case .passwordMismatch: "Your passwords don’t match."
            }
        }
    }
}
