import Foundation
import FirebaseAuth
@testable import Treachery_iOS

/// Stands in for Firebase Auth. Tests can't build a FirebaseAuth `User`, so
/// the sign-in methods throw and the auth state listener never fires; tests
/// sign in and out through `AuthViewModel.authStateDidChange(to:)`, or
/// provision once through `AuthViewModel.provisionProfile(for:)`.
final class MockAuthManaging: AuthManaging {

    enum Unsupported: Error {
        case needsAFirebaseUser
    }

    /// What `reloadAccount(userId:)` reports.
    var accountStatus: AccountStatus = .exists
    /// Thrown by `signOut()`.
    var signOutError: Error?
    /// Thrown by the sign-in methods, `verifyPhoneNumber` and
    /// `resetPassword` in place of their usual outcome.
    var signInError: Error?
    /// Runs once inside `reloadAccount(userId:)`, while a provisioning
    /// attempt is in flight, so a test can act mid-attempt.
    var whileReloadingAccount: (@MainActor () async -> Void)?

    private(set) var reloadAccountCalls: [String] = []
    private(set) var signOutCallCount = 0

    var currentUser: User? { nil }

    func signInAnonymously() async throws -> User { throw signInError ?? Unsupported.needsAFirebaseUser }
    func signIn(email: String, password: String) async throws -> User { throw signInError ?? Unsupported.needsAFirebaseUser }
    func signUp(email: String, password: String) async throws -> User { throw signInError ?? Unsupported.needsAFirebaseUser }

    func resetPassword(email: String) async throws {
        if let signInError { throw signInError }
    }

    func verifyPhoneNumber(_ phoneNumber: String) async throws -> String { throw signInError ?? Unsupported.needsAFirebaseUser }

    func signInWithPhoneCode(verificationID: String, code: String) async throws -> User {
        throw signInError ?? Unsupported.needsAFirebaseUser
    }

    func signOut() throws {
        signOutCallCount += 1
        if let signOutError { throw signOutError }
    }

    func addAuthStateListener(_ callback: @escaping (User?) -> Void) -> Any { NSObject() }
    func removeAuthStateListener(_ handle: Any) {}

    func reloadAccount(userId: String) async -> AccountStatus {
        reloadAccountCalls.append(userId)
        if let inFlight = whileReloadingAccount {
            // One-shot, so a test can't recurse into it by accident.
            whileReloadingAccount = nil
            await inFlight()
        }
        return accountStatus
    }
}
