//
//  AuthViewModel.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import Foundation
import FirebaseAuth
import os

enum AuthState {
    case loading
    case authenticated(User)
    case unauthenticated
}

@MainActor
final class AuthViewModel: ObservableObject {

    @Published var authState: AuthState = .loading
    @Published var errorMessage: String?
    @Published var isNewUser: Bool = false

    private let firebaseManager: AuthManaging
    private let firestoreManager: FirestoreManaging
    private let profileProvisioner: ProfileProvisioner
    private var authStateHandle: Any?

    private static let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "Auth")

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

    /// Whether the signed-in account is a guest's (Firebase anonymous auth).
    /// A guest account can't be signed back into once signed out.
    var isGuest: Bool {
        if case .authenticated(let user) = authState {
            return user.isAnonymous
        }
        return false
    }

    /// - Parameter now: The clock profile provisioning reads when Firebase
    ///   Auth doesn't say when an account was created.
    init(
        firebaseManager: AuthManaging = FirebaseManager(),
        firestoreManager: FirestoreManaging = FirestoreManager(),
        now: @escaping () -> Date = Date.init
    ) {
        self.firebaseManager = firebaseManager
        self.firestoreManager = firestoreManager
        self.profileProvisioner = ProfileProvisioner(firestore: firestoreManager, now: now)
        listenToAuthState()
    }

    deinit {
        if let handle = authStateHandle {
            firebaseManager.removeAuthStateListener(handle)
        }
    }

    // MARK: - Auth State Listener

    /// Profile provisioning runs from here and nowhere else: Firebase Auth
    /// calls this once per sign-in. When the sign-in methods provisioned
    /// too, two runs could race, one skipping the name prompt or replacing a
    /// profile the other had just created.
    private func listenToAuthState() {
        authStateHandle = firebaseManager.addAuthStateListener { [weak self] user in
            Task { @MainActor in
                if let user = user {
                    let account = SignedInAccount(user)
                    self?.authState = .authenticated(user)
                    AnalyticsService.setUserId(user.uid)
                    AnalyticsService.setUserProperties(["auth_method": account.authMethod.rawValue])
                    await self?.provisionProfile(for: account)
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
            _ = try await firebaseManager.signInAnonymously()
            AnalyticsService.trackEvent("sign_in", params: ["method": "guest"])
        } catch {
            report(error, while: "guest sign-in")
        }
    }

    // MARK: - Email/Password Auth

    func signIn(email: String, password: String) async {
        errorMessage = nil
        do {
            _ = try await firebaseManager.signIn(email: email, password: password)
            AnalyticsService.trackEvent("sign_in", params: ["method": "email"])
        } catch {
            report(error, while: "email sign-in")
        }
    }

    func signUp(email: String, password: String) async {
        errorMessage = nil
        do {
            _ = try await firebaseManager.signUp(email: email, password: password)
            AnalyticsService.trackEvent("sign_up", params: ["method": "email"])
        } catch {
            report(error, while: "sign-up")
        }
    }

    func resetPassword(email: String) async {
        errorMessage = nil
        do {
            try await firebaseManager.resetPassword(email: email)
        } catch {
            report(error, while: "password reset")
        }
    }

    // MARK: - Phone Auth

    func verifyPhoneNumber(_ phoneNumber: String) async -> String? {
        errorMessage = nil
        do {
            return try await firebaseManager.verifyPhoneNumber(phoneNumber)
        } catch {
            report(error, while: "sending a phone code")
            return nil
        }
    }

    func signInWithPhoneCode(verificationID: String, code: String) async {
        errorMessage = nil
        do {
            _ = try await firebaseManager.signInWithPhoneCode(verificationID: verificationID, code: code)
            AnalyticsService.trackEvent("sign_in", params: ["method": "phone"])
        } catch {
            report(error, while: "phone sign-in")
        }
    }

    // MARK: - Errors

    /// Shows the sign-in screens a plain sentence for `error` (never
    /// Firebase's own text) and logs the error itself.
    private func report(_ error: any Error, while action: String) {
        Self.logger.error("\(action, privacy: .public) failed: \(String(describing: error), privacy: .private)")
        errorMessage = UserFacingError(error).message
    }

    // MARK: - Onboarding

    func completeOnboarding() {
        isNewUser = false
    }

    /// Saves the name chosen during onboarding, writing only `display_name`.
    /// Returns once the server has it; throws if it couldn't be saved, for
    /// the caller to report.
    func updateDisplayName(_ name: String) async throws {
        guard let userId = currentUserId else { throw FirebaseManager.AuthError.notAuthenticated }
        do {
            try await firestoreManager.updateDisplayName(name, forUserId: userId)
        } catch {
            Self.logger.error("Saving the chosen display name failed: \(String(describing: error), privacy: .private)")
            throw error
        }
    }

    // MARK: - Profile Provisioning

    /// Makes sure the signed-in account has a usable profile (see
    /// `ProfileProvisioner`), asks for a name when the profile's is a
    /// placeholder, and signs out if Firebase Auth says the account no
    /// longer exists. Only the auth state listener calls this in the app.
    func provisionProfile(for account: SignedInAccount) async {
        let outcome = await profileProvisioner.provision(account) {
            await firebaseManager.reloadAccount(userId: account.uid)
        }
        if outcome == .accountGone {
            signOutDeletedAccount()
        }
        if outcome.needsName {
            isNewUser = true
        }
    }

    /// Ends a session whose account no longer exists. FirebaseAuth normally
    /// has already signed it out; this makes sure, and the auth state
    /// listener then shows the signed-out screen.
    private func signOutDeletedAccount() {
        do {
            try firebaseManager.signOut()
        } catch {
            Self.logger.error("Couldn't sign out an account that no longer exists: \(String(describing: error), privacy: .private)")
        }
    }
}

// MARK: - SessionEnding

extension AuthViewModel: SessionEnding {
    /// Signs out, throwing on failure for the caller to report: the Profile
    /// screen shows a failed Sign Out under the button, and after account
    /// deletion keeps the user on a blocking screen until sign-out succeeds.
    func endSession() throws {
        errorMessage = nil
        try firebaseManager.signOut()
        AnalyticsService.trackEvent("sign_out")
    }
}
