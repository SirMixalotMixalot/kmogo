import Foundation

enum AccountRecovery {
    static let redirectURL = URL(string: "roam://auth/recovery")!
    static let minimumPasswordLength = 6

    static func isCallback(_ url: URL) -> Bool {
        url.scheme?.lowercased() == redirectURL.scheme
            && url.host?.lowercased() == redirectURL.host
            && url.path == redirectURL.path
            && url.user == nil && url.password == nil && url.port == nil
    }
}
