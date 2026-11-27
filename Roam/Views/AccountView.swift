import SwiftUI

struct AccountView: View {
    @Environment(AppStore.self) private var store
    @Environment(AccountStore.self) private var account
    @State private var creatingAccount = false
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var importJourney = false
    @State private var showForgotPassword = false
    @State private var showSignupConfirmation = false

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && (!creatingAccount || (!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    && password.count >= AccountRecovery.minimumPasswordLength))
    }

    var body: some View {
        Form {
            if let session = account.session {
                Section("Signed in") {
                    if let profile = account.profile { Text(profile.displayName) }
                    Text(session.user.email ?? "Roam account").foregroundStyle(.secondary)
                }
                if account.profile == nil {
                    Section {
                        Button("Load profile") { Task { await account.refresh(store: store) } }
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await account.signOut(store: store) }
                    }
                    .disabled(account.isBusy || store.state.activeRun != nil)
                } footer: {
                    Text("Your journey is saved on this device for this account.")
                }
            } else if showSignupConfirmation {
                Section {
                    Label("Check your email", systemImage: "envelope.badge")
                        .font(.headline)
                    Text("Confirm \(email.trimmingCharacters(in: .whitespacesAndNewlines)), then return to Roam to sign in.")
                    Button("Back to sign in") {
                        password = ""
                        account.notice = nil
                        creatingAccount = false
                        showSignupConfirmation = false
                    }
                }
            } else {
                Section {
                    Picker("Account", selection: $creatingAccount) {
                        Text("Sign in").tag(false)
                        Text("Create account").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .disabled(account.isBusy)
                    .onChange(of: creatingAccount) { _, _ in
                        password = ""
                        account.errorMessage = nil
                        account.authenticationAlert = nil
                        account.notice = nil
                        showSignupConfirmation = false
                    }
                    if creatingAccount {
                        TextField("Display name", text: $name)
                            .textContentType(.nickname)
                            .onChange(of: name) { _, value in name = String(value.prefix(40)) }
                    }
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if creatingAccount {
                        SecureField("Password", text: $password)
                            .textContentType(.newPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit { if canSubmit { Task { await submit() } } }
                    } else {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit { if canSubmit { Task { await submit() } } }
                    }
                }
                .disabled(account.isBusy)
                if store.state.profile != nil {
                    Section {
                        Toggle("Import this device’s guest journey", isOn: $importJourney)
                    } footer: {
                        Text("Uses your guest journey when this account has no saved journey on this device.")
                    }
                }
                Section {
                    Button(creatingAccount ? "Create account" : "Sign in") {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit || account.isBusy || store.state.activeRun != nil)
                    if !creatingAccount {
                        Button("Forgot password?") {
                            account.errorMessage = nil
                            account.notice = nil
                            showForgotPassword = true
                        }
                        .disabled(account.isBusy || store.state.activeRun != nil)
                    }
                } footer: {
                    if creatingAccount {
                        Text("Use at least 6 characters for your password. Confirm your email before signing in.")
                    }
                }
            }
            if store.state.activeRun != nil {
                Section { Text("Finish your current run before changing accounts.").foregroundStyle(.secondary) }
            }
            AccountFeedback()
            if account.isBusy { ProgressView().frame(maxWidth: .infinity) }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await account.refresh(store: store) }
        .onAppear { name = store.state.profile?.name ?? "" }
        .onDisappear { password = "" }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView(initialEmail: email)
        }
        .alert(account.authenticationAlert?.title ?? "Account", isPresented: Binding(
            get: { account.authenticationAlert != nil },
            set: { if !$0 { account.authenticationAlert = nil } })) {
                Button("OK", role: .cancel) { account.authenticationAlert = nil }
            } message: { Text(account.authenticationAlert?.message ?? "") }
    }

    private func submit() async {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit, !account.isBusy, store.state.activeRun == nil else { return }
        if creatingAccount {
            let succeeded = await account.signUp(email: address, password: password, name: name,
                                                 importJourney: importJourney, store: store)
            if succeeded, account.session == nil { showSignupConfirmation = true }
        } else {
            await account.signIn(email: address, password: password, importJourney: importJourney, store: store)
        }
        // Keep the credential intact until the successful form is removed so Password AutoFill
        // can offer to save it. Failed requests also retain the suggested password for a retry.
    }
}

struct AccountFeedback: View {
    @Environment(AccountStore.self) private var account

    var body: some View {
        if let error = account.errorMessage {
            Section { Text(error).foregroundStyle(.red) }
        }
        if let notice = account.notice {
            Section { Text(notice).foregroundStyle(.secondary) }
        }
    }
}
