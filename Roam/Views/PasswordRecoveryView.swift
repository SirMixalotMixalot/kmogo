import SwiftUI

struct ForgotPasswordView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var email: String
    @State private var sent = false

    init(initialEmail: String) {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section {
                        Label("Check your email", systemImage: "envelope.badge").font(.headline)
                        Text(account.notice ?? "If an account exists for this email, we sent a reset link.")
                        Button("Done") { dismiss() }
                    }
                } else {
                    Section {
                        TextField("Account email", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.send)
                            .onSubmit { Task { await send() } }
                        Button("Send reset link") { Task { await send() } }
                            .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || account.isBusy)
                    } footer: {
                        Text("Open the email link on this iPhone. You’ll return to Roam to choose a new password.")
                    }
                    if let error = account.errorMessage {
                        Section { Text(error).foregroundStyle(.red) }
                    }
                }
                if account.isBusy { ProgressView().frame(maxWidth: .infinity) }
            }
            .navigationTitle("Forgot password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func send() async {
        guard !account.isBusy, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sent = await account.requestPasswordReset(email: email)
    }
}

struct PasswordRecoveryView: View {
    @Environment(AppStore.self) private var store
    @Environment(AccountStore.self) private var account
    @State private var password = ""
    @State private var confirmation = ""

    private var canSubmit: Bool {
        password.count >= AccountRecovery.minimumPasswordLength && password == confirmation && !account.isBusy
    }

    var body: some View {
        NavigationStack {
            Form {
                if account.passwordUpdated {
                    Section {
                        Label("Password updated", systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(.green)
                        Text("Use your new password the next time you sign in.")
                        Button("Continue to Roam") { account.finishPasswordRecovery() }
                    }
                } else {
                    Section {
                        TextField("Email", text: .constant(account.session?.user.email ?? ""))
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .allowsHitTesting(false)
                        SecureField("New password", text: $password)
                            .textContentType(.newPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Confirm new password", text: $confirmation)
                            .textContentType(.newPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { if canSubmit { Task { await save() } } }
                    } footer: {
                        Text("Use at least \(AccountRecovery.minimumPasswordLength) characters.")
                    }
                    .disabled(account.isBusy)
                    Section {
                        Button("Update password") { Task { await save() } }
                            .disabled(!canSubmit)
                        Button("Cancel and sign out", role: .cancel) {
                            Task { await account.signOut(store: store) }
                        }
                        .disabled(account.isBusy)
                    }
                    AccountFeedback()
                }
                if account.isBusy { ProgressView().frame(maxWidth: .infinity) }
            }
            .navigationTitle("Choose a new password")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func save() async {
        guard canSubmit else { return }
        await account.updateRecoveredPassword(password, confirmation: confirmation)
        // The success state removes these fields before their values are discarded.
    }
}
