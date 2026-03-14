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

    func signIn(email: String, password: String) async throws -> User {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        return result.user
    }

    func signUp(email: String, password: String) async throws -> User {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        return result.user
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    func resetPassword(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func changePassword(newPassword: String) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.notAuthenticated
        }
        try await user.updatePassword(to: newPassword)
    }

    // MARK: - Phone Auth

    func sendPhoneVerificationCode(to phoneNumber: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil) { verificationID, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let verificationID = verificationID {
                    continuation.resume(returning: verificationID)
                } else {
                    continuation.resume(throwing: AuthError.verificationFailed)
                }
            }
        }
    }

    func verifyPhoneCode(verificationID: String, verificationCode: String) async throws -> User {
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: verificationCode
        )
        let result = try await Auth.auth().signIn(with: credential)
        return result.user
    }
}

// MARK: - Errors
extension FirebaseManager {
    enum AuthError: LocalizedError {
        case notAuthenticated
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "No authenticated user found."
            case .verificationFailed:
                return "Phone verification failed. Please try again."
            }
        }
    }
}
