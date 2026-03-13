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

    init(firebaseManager: FirebaseManager = FirebaseManager()) {
        self.firebaseManager = firebaseManager
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
                } else {
                    self?.authState = .unauthenticated
                }
            }
        }
    }

    // MARK: - Actions

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
            _ = try await firebaseManager.signUp(email: email, password: password)
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
}
