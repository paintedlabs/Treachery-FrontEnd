//
//  FirebaseManager.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 9/10/24.
//

import Foundation
import FirebaseAuth
import os

struct FirebaseManager: AuthManaging {

    private static let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "Auth")

    var currentUser: User? {
        Auth.auth().currentUser
    }

    // MARK: - Anonymous Auth

    func signInAnonymously() async throws -> User {
        let result = try await Auth.auth().signInAnonymously()
        return result.user
    }

    // MARK: - Email/Password Auth

    func signIn(email: String, password: String) async throws -> User {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        return result.user
    }

    func signUp(email: String, password: String) async throws -> User {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        return result.user
    }

    func resetPassword(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    // MARK: - Phone Auth

    func verifyPhoneNumber(_ phoneNumber: String) async throws -> String {
        let verificationID = try await PhoneAuthProvider.provider(auth: Auth.auth()).verifyPhoneNumber(phoneNumber, uiDelegate: nil)
        return verificationID
    }

    func signInWithPhoneCode(verificationID: String, code: String) async throws -> User {
        let credential = PhoneAuthProvider.provider(auth: Auth.auth()).credential(
            withVerificationID: verificationID,
            verificationCode: code
        )
        let result = try await Auth.auth().signIn(with: credential)
        return result.user
    }

    // MARK: - Sign Out

    func signOut() throws {
        try Auth.auth().signOut()
    }

    // MARK: - Auth State Listener

    func addAuthStateListener(_ callback: @escaping (User?) -> Void) -> Any {
        Auth.auth().addStateDidChangeListener { _, user in
            callback(user)
        }
    }

    func removeAuthStateListener(_ handle: Any) {
        if let handle = handle as? AuthStateDidChangeListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Account Status

    func reloadAccount(userId: String) async -> AccountStatus {
        guard let user = Auth.auth().currentUser, user.uid == userId else {
            Self.logger.notice("Not reloading the account: it is no longer the signed-in one")
            return .unknown
        }
        do {
            try await user.reload()
            return .exists
        } catch {
            let nsError = error as NSError
            Self.logger.notice("Reloading the account failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            return AccountStatus(reloadError: error)
        }
    }
}

extension AccountStatus {
    /// Classifies a failed `User.reload()`.
    /// - Only the errors FirebaseAuth itself treats as the end of a session
    ///   (`User.signOutIfTokenIsInvalid`) mean the account is gone.
    /// - `keychainError` means the account exists: reload throws it only
    ///   when saving the user locally fails, after the server has refreshed
    ///   the account's token or returned its details.
    /// - Anything else, such as being offline, says nothing about the
    ///   account. Deliberately stricter than "create unless offline": a
    ///   profile created for an account deleted elsewhere would bring its
    ///   data back.
    init(reloadError error: Error) {
        let error = error as NSError
        guard error.domain == AuthErrors.domain,
              let code = AuthErrorCode(rawValue: error.code) else {
            self = .unknown
            return
        }
        switch code {
        case .userNotFound, .userDisabled, .invalidUserToken, .userTokenExpired:
            self = .gone
        case .keychainError:
            self = .exists
        default:
            self = .unknown
        }
    }
}

// MARK: - Errors
extension FirebaseManager {
    enum AuthError: LocalizedError {
        case notAuthenticated

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "No authenticated user found."
            }
        }
    }
}
