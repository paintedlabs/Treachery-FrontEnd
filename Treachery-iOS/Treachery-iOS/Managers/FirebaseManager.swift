//
//  FirebaseManager.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 9/10/24.
//

import Foundation
import FirebaseAuth

struct FirebaseManager {

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
        let verificationID = try await PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil)
        return verificationID
    }

    func signInWithPhoneCode(verificationID: String, code: String) async throws -> User {
        let credential = PhoneAuthProvider.provider().credential(
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
