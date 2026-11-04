import Foundation
import FirebaseAuth

protocol AuthManaging {
    var currentUser: User? { get }
    func signInAnonymously() async throws -> User
    func signIn(email: String, password: String) async throws -> User
    func signUp(email: String, password: String) async throws -> User
    func resetPassword(email: String) async throws
    func verifyPhoneNumber(_ phoneNumber: String) async throws -> String
    func signInWithPhoneCode(verificationID: String, code: String) async throws -> User
    func signOut() throws
    func addAuthStateListener(_ callback: @escaping (User?) -> Void) -> Any
    func removeAuthStateListener(_ handle: Any)
    /// Reloads the signed-in account `userId` from Firebase Auth to learn
    /// whether it still exists. Never throws:
    /// - `.exists`: the reload succeeded, or it failed with `keychainError`.
    ///   FirebaseAuth throws that only after its server has answered for the
    ///   account, when saving the user on the device fails, so the account
    ///   exists but the `User` may not be refreshed.
    /// - `.gone`: the reload failed with an error that ends the session.
    /// - `.unknown`: any other failure, or `userId` is no longer the
    ///   signed-in account (then nothing is reloaded).
    func reloadAccount(userId: String) async -> AccountStatus
}

/// What reloading the signed-in account from Firebase Auth found.
enum AccountStatus: Equatable {
    /// Auth confirmed the account exists.
    case exists
    /// Auth no longer accepts this session: the account was deleted or
    /// disabled, or its sign-in was revoked. FirebaseAuth signs such a
    /// session out on its own.
    case gone
    /// The check didn't finish (offline, say, or a server error), or the
    /// account is no longer the signed-in one. Nothing is known about it.
    case unknown
}
