//
//  AuthViewModel.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import Foundation
import FirebaseAuth

enum AuthState {
    case loading
    case authenticated(User)
    case unauthenticated
}

@MainActor
final class AuthViewModel: ObservableObject {

    @Published var authState: AuthState = .loading
    @Published var errorMessage: String?

    // Phone auth state
    @Published var verificationID: String?
    @Published var isAwaitingVerification = false
    @Published var isSendingCode = false

    private let firebaseManager: FirebaseManager
    private let firestoreManager: FirestoreManager
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    var isAuthenticated: Bool {
        if case .authenticated = authState { return true }
        return false
    }

    var currentUserId: String? {
        if case .authenticated(let user) = authState {
            return user.uid
        }
        return nil
    }

    init(
        firebaseManager: FirebaseManager = FirebaseManager(),
        firestoreManager: FirestoreManager = FirestoreManager()
    ) {
        self.firebaseManager = firebaseManager
        self.firestoreManager = firestoreManager
        listenToAuthState()
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Auth State Listener

    private func listenToAuthState() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                if let user = user {
                    self?.authState = .authenticated(user)
                    await self?.createUserDocumentIfNeeded(for: user)
                } else {
                    self?.authState = .unauthenticated
                }
            }
        }
    }

    // MARK: - Email/Password Actions

    func signIn(email: String, password: String) async {
        errorMessage = nil
        do {
            _ = try await firebaseManager.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signUp(email: String, password: String) async {
        errorMessage = nil
        do {
            let user = try await firebaseManager.signUp(email: email, password: password)
            await createUserDocumentIfNeeded(for: user)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        errorMessage = nil
        do {
            try firebaseManager.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetPassword(email: String) async {
        errorMessage = nil
        do {
            try await firebaseManager.resetPassword(email: email)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Phone Auth Actions

    func sendVerificationCode(phoneNumber: String) async {
        errorMessage = nil
        isSendingCode = true
        do {
            let id = try await firebaseManager.sendPhoneVerificationCode(to: phoneNumber)
            verificationID = id
            isAwaitingVerification = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSendingCode = false
    }

    func verifyCode(_ code: String) async {
        guard let verificationID = verificationID else {
            errorMessage = "No verification ID. Please request a new code."
            return
        }
        errorMessage = nil
        do {
            let user = try await firebaseManager.verifyPhoneCode(
                verificationID: verificationID,
                verificationCode: code
            )
            await createUserDocumentIfNeeded(for: user)
            // Auth state listener will fire and update authState
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelPhoneVerification() {
        verificationID = nil
        isAwaitingVerification = false
        errorMessage = nil
    }

    // MARK: - User Document Creation

    private func createUserDocumentIfNeeded(for user: User) async {
        do {
            let existingUser = try await firestoreManager.getUser(id: user.uid)
            if existingUser == nil {
                let newUser = TreacheryUser(
                    id: user.uid,
                    displayName: user.displayName ?? user.phoneNumber ?? "Player",
                    email: user.email,
                    phoneNumber: user.phoneNumber,
                    friendIds: [],
                    createdAt: Date()
                )
                try await firestoreManager.createUser(newUser)
            }
        } catch {
            // Non-fatal: user can still use the app
            print("Failed to create user document: \(error)")
        }
    }
}
