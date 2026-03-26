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
}
