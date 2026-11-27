import Foundation
import Supabase
import XCTest
@testable import Roam

@MainActor
final class PasswordRecoveryTests: XCTestCase {
    private var account: AccountStore!
    private var store: AppStore!
    private var transport: URLSession!

    override func setUp() async throws {
        RecoveryHTTPStub.state.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecoveryHTTPStub.self]
        transport = URLSession(configuration: configuration)
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://roam-auth.test")!, supabaseKey: "test-publishable-key",
            options: SupabaseClientOptions(
                auth: .init(storage: RecoveryMemoryStorage(), autoRefreshToken: false,
                            emitLocalSessionAsInitialSession: true),
                global: .init(session: transport)
            )
        )
        account = AccountStore(client: client)
        store = AppStore(fileURL: nil, notificationsEnabled: false)
    }

    override func tearDown() async throws {
        account = nil
        store = nil
        transport.invalidateAndCancel()
        transport = nil
    }

    func testResetRequestUsesTrimmedEmailExactRedirectAndPKCE() async throws {
        RecoveryHTTPStub.state.respond(to: "POST /auth/v1/recover", status: 200, json: [:])
        let sent = await account.requestPasswordReset(email: "  runner@example.com\n")
        XCTAssertTrue(sent)
        let request = try XCTUnwrap(RecoveryHTTPStub.state.requests.first)
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "redirect_to" })?.value, "roam://auth/recovery")
        let body = try body(of: request)
        XCTAssertEqual(body["email"] as? String, "runner@example.com")
        XCTAssertFalse((body["code_challenge"] as? String ?? "").isEmpty)
        XCTAssertEqual(body["code_challenge_method"] as? String, "s256")
        XCTAssertTrue(account.notice?.hasPrefix("If an account exists") == true)
        XCTAssertFalse(account.isRecoveringPassword)
    }

    func testRejectedResetRequestDoesNotShowSuccess() async {
        RecoveryHTTPStub.state.respond(to: "POST /auth/v1/recover", status: 429,
                                       json: ["msg": "Wait before requesting another email."])
        let sent = await account.requestPasswordReset(email: "runner@example.com")
        XCTAssertFalse(sent)
        XCTAssertNil(account.notice)
        XCTAssertNotNil(account.errorMessage)
        XCTAssertFalse(account.isBusy)
    }

    func testPasswordCannotChangeWithoutVerifiedRecovery() async {
        let updated = await account.updateRecoveredPassword("strong-password", confirmation: "strong-password")
        XCTAssertFalse(updated)
        XCTAssertTrue(RecoveryHTTPStub.state.requests.isEmpty)
        XCTAssertFalse(account.passwordUpdated)
    }

    func testIncorrectCredentialsProduceAnActionableSignInAlert() async {
        RecoveryHTTPStub.state.respond(to: "POST /auth/v1/token", status: 400,
            json: ["error_code": "invalid_credentials", "msg": "Invalid login credentials"])
        let signedIn = await account.signIn(email: "runner@example.com", password: "wrong-password",
                                            importJourney: false, store: store)
        XCTAssertFalse(signedIn)
        XCTAssertNil(account.session)
        XCTAssertEqual(account.authenticationAlert?.title, "Couldn’t sign in")
        XCTAssertTrue(account.authenticationAlert?.message.contains("email or password is incorrect") == true)
        XCTAssertTrue(account.authenticationAlert?.message.contains("Forgot password") == true)
        XCTAssertFalse(account.isBusy)
    }

    func testUnconfirmedEmailExplainsHowToFinishSignIn() async {
        RecoveryHTTPStub.state.respond(to: "POST /auth/v1/token", status: 400,
            json: ["error_code": "email_not_confirmed", "msg": "Email not confirmed"])
        let signedIn = await account.signIn(email: "runner@example.com", password: "strong-password",
                                            importJourney: false, store: store)
        XCTAssertFalse(signedIn)
        XCTAssertTrue(account.authenticationAlert?.message.hasPrefix("Confirm your email") == true)
    }

    func testInvalidSignupProducesItsOwnAlert() async {
        RecoveryHTTPStub.state.respond(to: "POST /auth/v1/signup", status: 422,
            json: ["error_code": "weak_password", "msg": "Password is too weak"])
        let created = await account.signUp(email: "runner@example.com", password: "weak", name: "Runner",
                                           importJourney: false, store: store)
        XCTAssertFalse(created)
        XCTAssertEqual(account.authenticationAlert?.title, "Couldn’t create account")
        XCTAssertTrue(account.authenticationAlert?.message.contains("stronger password") == true)
    }

    func testProfileSearchRequiresSignInAndSendsNormalizedUsernames() async throws {
        do {
            _ = try await account.searchProfiles("pat")
            XCTFail("Unsigned searches must fail")
        } catch { XCTAssertTrue(RecoveryHTTPStub.state.requests.isEmpty) }
        try await recover()
        RecoveryHTTPStub.state.respond(to: "POST /rest/v1/rpc/roam_search_profiles", status: 200, json: [[
            "user_id": "00000000-0000-4000-8000-000000000456", "display_name": "Patrick",
            "username": "patrick", "status": "none", "friendship_id": NSNull()
        ]])
        let profiles = try await account.searchProfiles(" @PAT ")
        XCTAssertEqual(profiles.first?.username, "patrick")
        let request = try XCTUnwrap(RecoveryHTTPStub.state.requests.last)
        XCTAssertEqual(try body(of: request)["p_query"] as? String, "pat")
        let count = RecoveryHTTPStub.state.requests.count
        let invalid = try await account.searchProfiles("p%")
        XCTAssertTrue(invalid.isEmpty)
        XCTAssertEqual(RecoveryHTTPStub.state.requests.count, count)
    }

    func testTakenUsernameHasAFriendlyError() async throws {
        try await recover()
        RecoveryHTTPStub.state.respond(to: "POST /rest/v1/rpc/roam_set_username", status: 409,
            json: ["code": "23505", "details": NSNull(), "hint": NSNull(), "message": "duplicate key"])
        let saved = await account.setUsername("patrick", store: store)
        XCTAssertFalse(saved)
        XCTAssertEqual(account.errorMessage, "That username is already taken. Try another one.")
    }

    func testExpiredLinkDoesNotAuthorizeRecoveryOrExposeTheCode() async {
        RecoveryHTTPStub.state.respond(to: "POST /auth/v1/token", status: 400,
                                       json: ["msg": "Expired code: private-test-code"])
        await account.openPasswordRecovery(URL(string: "roam://auth/recovery?code=private-test-code")!, store: store)
        XCTAssertFalse(account.isRecoveringPassword)
        XCTAssertNil(account.session)
        XCTAssertNotNil(account.recoveryLinkError)
        XCTAssertFalse(account.recoveryLinkError?.contains("private-test-code") == true)
        XCTAssertFalse(account.isOpeningRecoveryLink)
    }

    func testVerifiedRecoveryValidatesAndUpdatesPasswordThenCanFinish() async throws {
        try await recover()
        let before = RecoveryHTTPStub.state.requests.count
        let short = await account.updateRecoveredPassword("short", confirmation: "short")
        let mismatch = await account.updateRecoveredPassword("strong-password", confirmation: "different")
        XCTAssertFalse(short)
        XCTAssertFalse(mismatch)
        XCTAssertEqual(RecoveryHTTPStub.state.requests.count, before)

        RecoveryHTTPStub.state.respond(to: "PUT /auth/v1/user", status: 200, json: Self.user)
        let updated = await account.updateRecoveredPassword("strong-password", confirmation: "strong-password")
        XCTAssertTrue(updated)
        XCTAssertTrue(account.passwordUpdated)
        let request = try XCTUnwrap(RecoveryHTTPStub.state.requests.last)
        XCTAssertEqual(try body(of: request)["password"] as? String, "strong-password")
        account.finishPasswordRecovery()
        XCTAssertFalse(account.isRecoveringPassword)
        XCTAssertNotNil(account.session)
    }

    func testCancellingRecoverySignsOutAndRestoresGuestJourney() async throws {
        try await recover()
        RecoveryHTTPStub.state.respond(to: "POST /auth/v1/logout", status: 200, json: [:])
        await account.signOut(store: store)
        XCTAssertNil(account.session)
        XCTAssertNil(store.accountID)
        XCTAssertFalse(account.isRecoveringPassword)
    }

    func testOnlyTheExactRecoveryCallbackIsHandled() async {
        for value in ["roam://join/group", "https://auth/recovery?code=test",
                      "roam://auth.evil.test/recovery?code=test", "roam://user@auth/recovery?code=test",
                      "roam://auth:443/recovery?code=test", "roam://auth/recovery/extra?code=test"] {
            let url = URL(string: value)!
            XCTAssertFalse(AccountRecovery.isCallback(url), value)
            await account.openPasswordRecovery(url, store: store)
        }
        XCTAssertTrue(RecoveryHTTPStub.state.requests.isEmpty)
        XCTAssertTrue(AccountRecovery.isCallback(URL(string: "roam://auth/recovery?code=test")!))
    }

    private func recover() async throws {
        RecoveryHTTPStub.state.respond(to: "POST /auth/v1/recover", status: 200, json: [:])
        let sent = await account.requestPasswordReset(email: "runner@example.com")
        XCTAssertTrue(sent)
        RecoveryHTTPStub.state.respond(to: "POST /auth/v1/token", status: 200, json: [
            "access_token": "test-access-token", "refresh_token": "test-refresh-token",
            "token_type": "bearer", "expires_in": 3600,
            "expires_at": Int(Date.now.addingTimeInterval(3600).timeIntervalSince1970), "user": Self.user
        ])
        await account.openPasswordRecovery(URL(string: "roam://auth/recovery?code=verified-test-code")!, store: store)
        XCTAssertTrue(account.isRecoveringPassword)
        XCTAssertEqual(account.session?.user.email, "runner@example.com")
        let request = try XCTUnwrap(RecoveryHTTPStub.state.requests.last)
        XCTAssertFalse((try body(of: request)["code_verifier"] as? String ?? "").isEmpty)
    }

    private func body(of request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 1024)
            var result = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                guard count > 0 else { break }
                result.append(contentsOf: bytes.prefix(count))
            }
            data = result
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(data)) as? [String: Any])
    }

    private static let user: [String: Any] = [
        "id": "00000000-0000-4000-8000-000000000123", "aud": "authenticated",
        "role": "authenticated", "email": "runner@example.com", "app_metadata": [:],
        "user_metadata": [:], "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z"
    ]
}

private final class RecoveryMemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { lock.withLock { values[key] = nil } }
}

private final class RecoveryHTTPStub: URLProtocol, @unchecked Sendable {
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.state.response(for: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [String: (Int, Data)] = [:]
        private var received: [URLRequest] = []
        var requests: [URLRequest] { lock.withLock { received } }
        func reset() { lock.withLock { responses = [:]; received = [] } }
        func respond(to endpoint: String, status: Int, json: Any) {
            let data = try! JSONSerialization.data(withJSONObject: json)
            lock.withLock { responses[endpoint] = (status, data) }
        }
        func response(for request: URLRequest) -> (Int, Data) {
            lock.withLock {
                received.append(request)
                return responses["\(request.httpMethod ?? "GET") \(request.url!.path)"]
                    ?? (500, Data("{\"msg\":\"Unexpected test request\"}".utf8))
            }
        }
    }
}
