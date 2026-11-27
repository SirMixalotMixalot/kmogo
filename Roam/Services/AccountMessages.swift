import Foundation
import Supabase

struct AccountAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum AccountMessages {
    static func message(for error: Error) -> String {
        if let auth = error as? AuthError {
            switch auth.errorCode {
            case .invalidCredentials:
                return "Your email or password is incorrect. Try again, or use Forgot password to reset it."
            case .emailNotConfirmed:
                return "Confirm your email using the link in your inbox, then return to Roam to sign in."
            case .emailExists, .userAlreadyExists:
                return "An account with this email already exists. Sign in, or use Forgot password."
            case .weakPassword:
                return "Choose a stronger password, then try again."
            case .overRequestRateLimit, .overEmailSendRateLimit:
                return "Too many attempts. Wait a little before trying again."
            default:
                return "We couldn’t complete that account request. Please try again."
            }
        }
        if let network = error as? URLError {
            if network.code == .cancelled { return "The request was cancelled. Try again when you’re ready." }
            return "Couldn’t connect to Roam. Check your internet connection and try again."
        }
        if error is PostgrestError { return "Couldn’t load your account information. Please try again." }
        return error.localizedDescription
    }
}
