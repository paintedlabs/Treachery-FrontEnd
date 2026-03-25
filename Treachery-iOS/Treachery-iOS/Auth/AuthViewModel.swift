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
                    AnalyticsService.setUserId(user.uid)
                    AnalyticsService.setUserProperties(["auth_method": user.isAnonymous ? "guest" : "email"])
                    await self?.createUserDocumentIfNeeded(for: user)
                } else {
                    self?.authState = .unauthenticated
                    AnalyticsService.setUserId(nil)
                }
            }
        }
    }

    // MARK: - Guest Auth

    func signInAsGuest() async {
        errorMessage = nil
        do {
            let user = try await firebaseManager.signInAnonymously()
            await createUserDocumentIfNeeded(for: user)
            AnalyticsService.trackEvent("sign_in", params: ["method": "guest"])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Email/Password Auth

    func signIn(email: String, password: String) async {
        errorMessage = nil
        do {
            let user = try await firebaseManager.signIn(email: email, password: password)
            await createUserDocumentIfNeeded(for: user)
            AnalyticsService.trackEvent("sign_in", params: ["method": "email"])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signUp(email: String, password: String) async {
        errorMessage = nil
        do {
            let user = try await firebaseManager.signUp(email: email, password: password)
            await createUserDocumentIfNeeded(for: user)
            AnalyticsService.trackEvent("sign_up", params: ["method": "email"])
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

    // MARK: - Phone Auth

    func verifyPhoneNumber(_ phoneNumber: String) async -> String? {
        errorMessage = nil
        do {
            return try await firebaseManager.verifyPhoneNumber(phoneNumber)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func signInWithPhoneCode(verificationID: String, code: String) async {
        errorMessage = nil
        do {
            let user = try await firebaseManager.signInWithPhoneCode(verificationID: verificationID, code: code)
            await createUserDocumentIfNeeded(for: user)
            AnalyticsService.trackEvent("sign_in", params: ["method": "phone"])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sign Out

    func signOut() {
        errorMessage = nil
        do {
            try firebaseManager.signOut()
            AnalyticsService.trackEvent("sign_out")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - User Document Creation

    private func createUserDocumentIfNeeded(for user: User) async {
        do {
            let existingUser = try await firestoreManager.getUser(id: user.uid)
            if existingUser == nil {
                let displayName = user.displayName ?? user.email ?? "Guest"
                let newUser = TreacheryUser(
                    id: user.uid,
                    displayName: displayName,
                    email: user.email,
                    phoneNumber: user.phoneNumber,
                    friendIds: [],
                    createdAt: Date()
                )
                try await firestoreManager.createUser(newUser)
            }
        } catch {
            print("Failed to create user document: \(error)")
        }
    }
}
