//
//  PushNotificationRegistrar.swift
//  Treachery-iOS
//
//  Keeps this device's FCM token registered to whoever is signed in.
//

import Foundation
import os
import FirebaseFirestore
import FirebaseMessaging
import UIKit
import UserNotifications

/// Reports who is signed in as a uid, so the registrar never handles a
/// FirebaseAuth `User` (which tests can't construct).
protocol SignedInUserObserving {
    /// Calls `onChange` with the signed-in uid (nil when signed out) once after
    /// registering, then after every change, until the returned handle is removed.
    func observeSignedInUser(_ onChange: @escaping @MainActor (String?) -> Void) -> ListenerCancellable
}

/// Reports when the server has a user's public profile (`users/{uid}`).
protocol UserProfileObserving {
    /// Calls `onExists` once the server has `uid`'s public profile, straight away if it
    /// already does, until the returned handle is removed.
    func observeProfileExists(forUser uid: String, _ onExists: @escaping @MainActor () -> Void) -> ListenerCancellable
}

/// This device's FCM registration token.
protocol PushTokenProviding {
    /// The current token, minting a new one if the last was deleted. Fails until
    /// APNs has issued this device a token.
    func currentToken() async throws -> String
    /// Unregisters the current token, so pushes sent to it stop arriving here.
    func deleteToken() async throws
}

/// Permission to show notifications.
protocol NotificationAuthorizing {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
}

/// Keeps this device's FCM token registered to the signed-in account, and only to it.
///
/// - When someone becomes signed in, including a session restored at launch, it waits
///   until the server has their public profile, asks for notification permission if
///   that was never decided, then registers the current token for them. The wait
///   matters for new accounts: registerFcmToken (functions/src/callables/users.js)
///   merge-writes `users/{uid}`, so calling it first creates an empty profile, and
///   firestore.rules then deny the app's own profile creation for good.
/// - When FCM refreshes the token while someone is signed in, it registers the new one.
/// - When the signed-in account ends (sign-out, or a switch straight to another
///   account), it deletes the token so this device stops receiving that account's
///   game notifications. The server drops the dead token the next time a send to it
///   fails (functions/src/notifications.js), and the next sign-in mints a fresh one.
///
/// Work runs one operation at a time, in the order events arrive, so a sign-out's
/// deletion finishes before the next sign-in asks for a token. Failures are logged,
/// never shown, and retried: registration on the next sign-in or token refresh,
/// deletion when the app next becomes active while signed out, at the next sign-in
/// or at the next launch (the pending deletion is persisted).
@MainActor
final class PushNotificationRegistrar {

    private enum Session: Equatable {
        /// Before the first auth callback of this launch.
        case unknown
        case signedOut
        /// Signed in, until the server has the account's public profile.
        case awaitingProfile(uid: String)
        /// Signed in, with a public profile on the server.
        case signedIn(uid: String)

        var uid: String? {
            switch self {
            case .unknown, .signedOut:
                return nil
            case .awaitingProfile(let uid), .signedIn(let uid):
                return uid
            }
        }
    }

    private struct Registration: Equatable {
        let uid: String
        let token: String
    }

    static let pendingDeletionKey = "pushNotificationRegistrar.tokenDeletionPending"

    private let signedInUser: SignedInUserObserving
    private let profiles: UserProfileObserving
    private let tokens: PushTokenProviding
    private let cloudFunctions: CloudFunctionsProtocol
    private let notificationAuthorization: NotificationAuthorizing
    private let notificationCenter: NotificationCenter
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "PushNotifications")

    private var session = Session.unknown
    /// The last token FCM handed the app delegate. Used when `currentToken()`
    /// fails because APNs hasn't answered yet at launch.
    private var deliveredToken: String?
    /// What the server holds for this device, as far as this launch knows.
    private var registration: Registration?
    private var hasRequestedAuthorization = false
    private var authListener: ListenerCancellable?
    private var profileListener: ListenerCancellable?
    private var activationObserver: NSObjectProtocol?
    private var queue: Task<Void, Never>?

    /// - Parameter notificationCenter: Where UIKit posts `didBecomeActiveNotification`.
    init(
        signedInUser: SignedInUserObserving,
        profiles: UserProfileObserving,
        tokens: PushTokenProviding,
        cloudFunctions: CloudFunctionsProtocol,
        notificationAuthorization: NotificationAuthorizing,
        notificationCenter: NotificationCenter,
        defaults: UserDefaults
    ) {
        self.signedInUser = signedInUser
        self.profiles = profiles
        self.tokens = tokens
        self.cloudFunctions = cloudFunctions
        self.notificationAuthorization = notificationAuthorization
        self.notificationCenter = notificationCenter
        self.defaults = defaults
    }

    deinit {
        authListener?.remove()
        profileListener?.remove()
        if let activationObserver {
            notificationCenter.removeObserver(activationObserver)
        }
    }

    /// Starts following sign-in changes and app activations. Call once, after Firebase is configured.
    func start() {
        guard authListener == nil else { return }
        authListener = signedInUser.observeSignedInUser { [weak self] uid in
            self?.signedInUserDidChange(to: uid)
        }
        activationObserver = notificationCenter.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applicationDidBecomeActive() }
        }
    }

    /// Forwarded from `MessagingDelegate`. FCM reports nil after a deletion.
    func registrationTokenDidChange(_ token: String?) {
        deliveredToken = token
        // Before the profile exists, the sign-in's own registration picks up the current token.
        guard let token, case .signedIn(let uid) = session else { return }
        enqueue { await self.register(token, for: uid) }
    }

    /// Returns once all queued work has finished. Tests await this instead of sleeping.
    func waitUntilIdle() async {
        while let current = queue {
            await current.value
            if queue == current { return }
        }
    }

    // MARK: - Events

    private func signedInUserDidChange(to uid: String?) {
        let previous = session
        guard previous == .unknown || uid != previous.uid else { return }
        profileListener?.remove()
        profileListener = nil

        if previous.uid != nil {
            // Persisted before any await, so a deletion that never ran is retried next launch.
            isTokenDeletionPending = true
            registration = nil
        }
        // Queued first, so a pending deletion finishes before the next account registers.
        enqueue { await self.deleteTokenIfPending() }

        guard let uid else {
            session = .signedOut
            return
        }
        session = .awaitingProfile(uid: uid)
        let listener = profiles.observeProfileExists(forUser: uid) { [weak self] in
            self?.profileDidAppear(for: uid)
        }
        // The profile may already have been reported, from inside the call.
        if session == .awaitingProfile(uid: uid) {
            profileListener = listener
        } else {
            listener.remove()
        }
    }

    private func profileDidAppear(for uid: String) {
        guard session == .awaitingProfile(uid: uid) else { return }
        session = .signedIn(uid: uid)
        profileListener?.remove()
        profileListener = nil
        enqueue { await self.accountDidBecomeReady(uid) }
    }

    /// A sign-out deletion that failed is otherwise retried only at the next sign-in or
    /// launch, and until then the previous account's notifications keep arriving here.
    private func applicationDidBecomeActive() {
        guard session == .signedOut, isTokenDeletionPending else { return }
        enqueue { await self.deleteTokenIfPending() }
    }

    // MARK: - Operations

    private func accountDidBecomeReady(_ uid: String) async {
        // Skipped if that session already ended while this waited in the queue.
        guard session == .signedIn(uid: uid) else { return }
        await requestAuthorizationIfUndecided()
        await registerCurrentToken(for: uid)
    }

    private func requestAuthorizationIfUndecided() async {
        guard !hasRequestedAuthorization else { return }
        guard await notificationAuthorization.authorizationStatus() == .notDetermined else { return }
        hasRequestedAuthorization = true
        do {
            let granted = try await notificationAuthorization.requestAuthorization()
            logger.notice("Notification permission \(granted ? "granted" : "declined", privacy: .public)")
        } catch {
            logger.error("Notification permission request failed: \(Self.describe(error), privacy: .public)")
        }
    }

    private func registerCurrentToken(for uid: String) async {
        let token: String
        do {
            token = try await tokens.currentToken()
        } catch {
            guard let deliveredToken else {
                logger.notice("No FCM token yet (\(Self.describe(error), privacy: .public)); will register when FCM delivers one")
                return
            }
            token = deliveredToken
        }
        await register(token, for: uid)
    }

    private func register(_ token: String, for uid: String) async {
        let candidate = Registration(uid: uid, token: token)
        // Re-checked here because the session can change while this waits in the queue.
        guard session == .signedIn(uid: uid), registration != candidate else { return }
        do {
            try await cloudFunctions.registerFcmToken(token)
            if session == .signedIn(uid: uid) {
                registration = candidate
            }
            logger.notice("Registered this device for the signed-in account's notifications")
        } catch {
            logger.error(
                "Couldn't register the FCM token (\(Self.describe(error), privacy: .public)); will retry on the next sign-in or token refresh"
            )
        }
    }

    private func deleteTokenIfPending() async {
        guard isTokenDeletionPending else { return }
        do {
            try await tokens.deleteToken()
            isTokenDeletionPending = false
            deliveredToken = nil
            logger.notice("Deleted the FCM token; the previous account's notifications stop here")
        } catch {
            logger.error(
                """
                Couldn't delete the FCM token (\(Self.describe(error), privacy: .public)); \
                will retry when the app is next active, or at the next sign-in or launch
                """
            )
        }
    }

    // MARK: - Helpers

    private var isTokenDeletionPending: Bool {
        get { defaults.bool(forKey: Self.pendingDeletionKey) }
        set { defaults.set(newValue, forKey: Self.pendingDeletionKey) }
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task {
            await previous?.value
            await operation()
        }
    }

    /// Domain and code only: enough to diagnose, nothing that identifies the user or device.
    private static func describe(_ error: Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }
}

// MARK: - Live dependencies

/// Adapts `AuthManaging`'s FirebaseAuth listener to the uid-only seam.
struct AuthStateUserObserver: SignedInUserObserving {
    let authManager: AuthManaging

    func observeSignedInUser(_ onChange: @escaping @MainActor (String?) -> Void) -> ListenerCancellable {
        let handle = authManager.addAuthStateListener { user in
            let uid = user?.uid
            // FirebaseAuth always calls state listeners on the main thread
            // (Auth.swift `addStateDidChangeListener` documentation).
            MainActor.assumeIsolated { onChange(uid) }
        }
        return AuthStateListenerHandle(authManager: authManager, handle: handle)
    }
}

private struct AuthStateListenerHandle: ListenerCancellable {
    let authManager: AuthManaging
    let handle: Any

    func remove() {
        authManager.removeAuthStateListener(handle)
    }
}

/// The public profile's existence, from a Firestore listener on `users/{uid}`.
struct FirestoreUserProfileObserver: UserProfileObserving {
    let firestore: Firestore

    private static let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "PushNotifications")

    func observeProfileExists(forUser uid: String, _ onExists: @escaping @MainActor () -> Void) -> ListenerCancellable {
        let registration = firestore.collection("users").document(uid)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error {
                    let error = error as NSError
                    Self.logger.error(
                        """
                        Couldn't watch for the account's profile (\(error.domain, privacy: .public) \(error.code)); \
                        will register at the next sign-in or launch
                        """
                    )
                    return
                }
                // A profile the app has written but the server hasn't committed doesn't count yet.
                guard let snapshot, snapshot.exists, !snapshot.metadata.hasPendingWrites else { return }
                // Firestore calls listeners on the main queue (`FirestoreSettings.dispatchQueue`'s default).
                MainActor.assumeIsolated { onExists() }
            }
        return SnapshotListenerHandle(registration: registration)
    }
}

private struct SnapshotListenerHandle: ListenerCancellable {
    let registration: ListenerRegistration

    func remove() {
        registration.remove()
    }
}

/// The FCM token, from Firebase Messaging.
struct MessagingTokenProvider: PushTokenProviding {
    let messaging: Messaging

    func currentToken() async throws -> String {
        try await messaging.token()
    }

    func deleteToken() async throws {
        try await messaging.deleteToken()
    }
}

/// Notification permission, from the system.
struct UserNotificationAuthorization: NotificationAuthorizing {
    let center: UNUserNotificationCenter

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }
}
