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
    /// Signed in. The account is as Firebase Auth reported it at sign-in, a
    /// value tests can build, unlike FirebaseAuth's `User`. Firebase Auth
    /// reports again only when another account signs in, so a change to this
    /// one, such as a guest account later upgraded by linking, would need
    /// reporting here too.
    case authenticated(SignedInAccount)
    case unauthenticated
}

/// How far setting up the signed-in account's profile has got. One enum
/// rather than flags, so states like "asking for a name while no one is
/// signed in" can't be represented.
enum ProfileSetupState: Equatable, Sendable {
    /// No account is signed in.
    case noAccount
    /// Not set up yet: an attempt is running, or the last one was postponed
    /// (offline, say) and the next is due.
    case pending
    /// Set up with a placeholder name. The name prompt asks for the user's
    /// own until they save one or skip.
    case needsName
    /// Over: the profile is set up, or can't be (it's undecodable, or the
    /// account is gone).
    case finished
}

@MainActor
final class AuthViewModel: ObservableObject {

    @Published var authState: AuthState = .loading
    @Published var errorMessage: String?
    /// How far setting up the signed-in account's profile has got. It can
    /// finish while the tabs are open, when a retry sets the profile up late
    /// or the name prompt over them closes, so Profile and Friends load
    /// again when it does.
    @Published private(set) var profileSetupState: ProfileSetupState = .noAccount

    private let firebaseManager: AuthManaging
    private let firestoreManager: FirestoreManaging
    private let profileProvisioner: ProfileProvisioner
    private let clock: any Clock<Duration>
    private var authStateHandle: Any?

    /// Sets up the signed-in account's profile, retrying while that's
    /// postponed (`startProfileSetup(for:)`). Nil once the profile is set
    /// up, and while no one is signed in.
    private var profileSetup: Task<Void, Never>?
    /// The profile setup's wait before its next retry, while it waits.
    /// Cancelling it retries at once.
    private var profileSetupRetryWait: Task<Void, Never>?
    /// Callers of `retryProfileSetup()`, waiting for the attempt that's
    /// running or about to start to end.
    private var profileSetupWaiters: [CheckedContinuation<Void, Never>] = []

    private static let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "Auth")

    var isAuthenticated: Bool {
        if case .authenticated = authState { return true }
        return false
    }

    /// Whether the name prompt shows: the profile was just set up with a
    /// placeholder name.
    var isNewUser: Bool {
        profileSetupState == .needsName
    }

    var currentUserId: String? {
        if case .authenticated(let account) = authState {
            return account.uid
        }
        return nil
    }

    /// Whether the signed-in account is a guest's (Firebase anonymous auth).
    /// A guest account can't be signed back into once signed out.
    var isGuest: Bool {
        if case .authenticated(let account) = authState {
            return account.isAnonymous
        }
        return false
    }

    /// - Parameters:
    ///   - now: The clock profile provisioning reads when Firebase Auth
    ///     doesn't say when an account was created.
    ///   - clock: Times the retries of a postponed profile setup.
    init(
        firebaseManager: AuthManaging = FirebaseManager(),
        firestoreManager: FirestoreManaging = FirestoreManager(),
        now: @escaping () -> Date = Date.init,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.firebaseManager = firebaseManager
        self.firestoreManager = firestoreManager
        self.profileProvisioner = ProfileProvisioner(firestore: firestoreManager, now: now)
        self.clock = clock
        listenToAuthState()
    }

    deinit {
        profileSetup?.cancel()
        profileSetupRetryWait?.cancel()
        if let handle = authStateHandle {
            firebaseManager.removeAuthStateListener(handle)
        }
    }

    // MARK: - Auth State Listener

    /// Firebase Auth calls the listener when it's added, and then each time
    /// an account signs in or out; never twice in a row for one account.
    private func listenToAuthState() {
        authStateHandle = firebaseManager.addAuthStateListener { [weak self] user in
            let account = user.map { SignedInAccount($0) }
            Task { @MainActor in
                if let account {
                    AnalyticsService.setUserId(account.uid)
                    AnalyticsService.setUserProperties(["auth_method": account.authMethod.rawValue])
                } else {
                    AnalyticsService.setUserId(nil)
                }
                self?.authStateDidChange(to: account)
            }
        }
    }

    /// Shows the screens for `account`, or the signed-out ones for nil, and
    /// sets up the profile of an account that just signed in. The auth state
    /// listener calls this; tests call it in its place, since they can't
    /// build a FirebaseAuth `User`.
    ///
    /// Profile provisioning runs from here and nowhere else, one attempt at
    /// a time. When the sign-in methods provisioned too, two runs could race,
    /// one skipping the name prompt or replacing a profile the other had just
    /// created.
    func authStateDidChange(to account: SignedInAccount?) {
        guard let account else {
            stopProfileSetup()
            profileSetupState = .noAccount
            authState = .unauthenticated
            return
        }
        let isAnotherAccount = account.uid != currentUserId
        authState = .authenticated(account)
        if isAnotherAccount {
            startProfileSetup(for: account)
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

    /// Closes the name prompt once a name is saved or skipped, which
    /// finishes the profile setup.
    func completeOnboarding() {
        guard profileSetupState == .needsName else { return }
        profileSetupState = .finished
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

    // MARK: - Profile Setup

    /// How long a postponed profile setup waits before each retry: soon at
    /// first, then less often, and every five minutes from the fourth on.
    static let profileSetupRetryDelays: [Duration] = [.seconds(5), .seconds(30), .seconds(120), .seconds(300)]

    /// Brings a postponed profile setup's next retry forward to now, as when
    /// the app becomes active and may be back online. Does nothing while an
    /// attempt runs, whose answer is fresh, or when nothing needs setting up.
    func retryPostponedProfileSetup() {
        profileSetupRetryWait?.cancel()
    }

    /// Brings a postponed profile setup's next retry forward to now, then
    /// returns once that attempt, or the one already running, is over. Try
    /// Again on a screen that needs the profile calls this before reading
    /// it. Returns at once when nothing needs setting up.
    func retryProfileSetup() async {
        guard profileSetup != nil else { return }
        await withCheckedContinuation { continuation in
            profileSetupWaiters.append(continuation)
            retryPostponedProfileSetup()
        }
    }

    /// Starts setting up `account`'s profile: provisions it, and while that's
    /// postponed (offline, say) provisions again after each of
    /// `profileSetupRetryDelays`, the last one repeating, until it settles.
    /// Only this task provisions, so attempts never overlap. It holds the
    /// view model only while an attempt runs, not while it waits.
    private func startProfileSetup(for account: SignedInAccount) {
        stopProfileSetup()
        profileSetupState = .pending
        profileSetup = Task { [weak self] in
            var retry = 0
            while let wait = await self?.attemptProfileSetup(for: account, retry: retry) {
                await wait.value
                retry += 1
            }
        }
    }

    /// One attempt of the profile setup. Returns the wait before the next one
    /// if this one was postponed, or nil once the setup is over: the profile
    /// is set up or can't be, or the setup was stopped.
    private func attemptProfileSetup(for account: SignedInAccount, retry: Int) async -> Task<Void, Never>? {
        // Stopped while it waited.
        guard !Task.isCancelled else { return nil }
        profileSetupRetryWait = nil
        let outcome = await provisionProfile(for: account)
        // Stopped during the attempt, which released the waiters.
        guard !Task.isCancelled else { return nil }
        releaseProfileSetupWaiters()
        guard outcome == .postponed, currentUserId == account.uid else {
            profileSetup = nil
            return nil
        }
        let delays = Self.profileSetupRetryDelays
        let delay = delays[min(retry, delays.count - 1)]
        let wait = Task { [clock] in
            // Cancelled to retry early or to stop; the next attempt checks which.
            _ = try? await clock.sleep(for: delay)
        }
        profileSetupRetryWait = wait
        return wait
    }

    /// Stops the profile setup, if one runs, because its account signed out
    /// or another signed in. An attempt still running ends without acting on
    /// its outcome (`provisionProfile(for:)`).
    private func stopProfileSetup() {
        profileSetup?.cancel()
        profileSetup = nil
        profileSetupRetryWait?.cancel()
        profileSetupRetryWait = nil
        releaseProfileSetupWaiters()
    }

    private func releaseProfileSetupWaiters() {
        let waiters = profileSetupWaiters
        profileSetupWaiters = []
        waiters.forEach { $0.resume() }
    }

    // MARK: - Profile Provisioning

    /// One provisioning attempt: makes sure the signed-in account has a
    /// usable profile (see `ProfileProvisioner`), asks for a name when the
    /// profile's is a placeholder, and signs out if Firebase Auth says the
    /// account no longer exists. Unless it's postponed, it ends the setup
    /// (`profileSetupState`). An attempt whose task was cancelled, because
    /// the account signed out or another signed in meanwhile, doesn't act on
    /// its outcome. Only the profile setup calls this in the app.
    @discardableResult
    func provisionProfile(for account: SignedInAccount) async -> ProfileProvisioner.Outcome {
        let outcome = await profileProvisioner.provision(account) {
            await firebaseManager.reloadAccount(userId: account.uid)
        }
        guard !Task.isCancelled else { return outcome }
        if outcome == .accountGone {
            signOutDeletedAccount()
        }
        // Postponed, the setup is still pending: it tries again.
        if outcome != .postponed {
            profileSetupState = outcome.needsName ? .needsName : .finished
        }
        return outcome
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
