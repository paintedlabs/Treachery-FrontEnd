//
//  FirebaseAuthKeychainMigration.swift
//  Treachery-iOS
//
//  Keeps users signed in across the GoogleService-Info.plist change.
//

import Foundation
import os
import Security
import UIKit

/// The generic-password keychain calls `FirebaseAuthKeychainMigration` makes,
/// addressed by service and account. A protocol so the migration's decisions
/// can be tested against an in-memory fake.
protocol GenericPasswordKeychain {
    /// `errSecSuccess` if the item exists, `errSecItemNotFound` if it doesn't,
    /// or the error that stopped the lookup (such as `errSecInteractionNotAllowed`).
    func statusOfItem(withService service: String, account: String) -> OSStatus
    /// Changes only the item's service, so its data, accessibility and access group stay as they were.
    func moveItem(account: String, fromService: String, toService: String) -> OSStatus
    func deleteItem(withService service: String, account: String) -> OSStatus
}

/// Moves the signed-in Firebase Auth user to the keychain item the bundled
/// GoogleService-Info.plist reads. Runs before `FirebaseApp.configure()`, and
/// once per install.
///
/// FirebaseAuth keeps the signed-in user in a generic-password item whose
/// service is "firebase_auth_" + GOOGLE_APP_ID. Every build through v1.1.0
/// shipped app 1:573413045061:ios:48e9c6fc92abac6790442c, which was deleted from
/// the Firebase project; the current plist is the project's only iOS app. Without
/// this move the update signs everyone out, and guest (anonymous) accounts are
/// lost for good.
///
/// The item is moved rather than copied: a leftover legacy item would sign the
/// user back in to the old session if they later signed out on this build.
/// Restoring it under the new service works because Auth swaps the archived app
/// ID and API key for the current app's when it loads the user.
///
/// This relies on FirebaseAuth's private keychain layout in firebase-ios-sdk
/// 11.15.0 (the version the project resolves; re-check before upgrading):
/// - service: Auth.swift `keychainServiceName(for:)`, ~L1846-1857.
/// - account: AuthKeychainServices.swift `kAccountPrefix` (L22) and
///   `genericPasswordQuery` (~L224-235), Auth.swift `kUserKey` (L2423), and
///   FIRApp.m `kFIRDefaultAppName` (L49).
/// - query flag `kSecUseDataProtectionKeychain = true`; items are written with
///   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (`setItemLegacy`).
/// - restore: User.swift `auth` setter (~L1143-1152) and `init(coder:)` (~L1755-1766).
/// - locked keychain: Auth.swift `protectedDataInitialization` and
///   `addProtectedDataDidBecomeAvailableObserver` (~L1689-1770).
///
/// Remove it once installs that last ran v1.1.0 or earlier no longer matter:
/// anyone who updates from such a build straight to one without this migration
/// is signed out, and a guest loses their account.
struct FirebaseAuthKeychainMigration {

    enum Outcome: Equatable {
        /// An earlier launch finished the migration.
        case alreadyCompleted
        /// The bundled config still uses the legacy app ID, so Auth reads the legacy item itself.
        case notNeeded
        /// No legacy session: a fresh install, or the user was signed out.
        case nothingToMove
        /// The legacy session now lives under the current app's service.
        case moved
        /// Both existed. The current app's session wins and the legacy item is gone.
        case removedLegacyItem
        /// The keychain is locked (before the first unlock after a restart). Retried when it
        /// unlocks, and at the next launch.
        case deferredUntilUnlocked
        /// An unexpected keychain error. Retried next launch.
        case failed(OSStatus)
    }

    /// The deleted Firebase iOS app that every build through v1.1.0 shipped.
    static let legacyAppID = "1:573413045061:ios:48e9c6fc92abac6790442c"
    /// FirebaseAuth's account for the default app's signed-in user:
    /// "firebase_auth_1_" + "__FIRAPP_DEFAULT" + "_firebase_user".
    static let signedInUserAccount = "firebase_auth_1___FIRAPP_DEFAULT_firebase_user"
    static let completionKey = "firebaseAuthKeychainMigration.completed"

    private let keychain: GenericPasswordKeychain
    private let defaults: UserDefaults
    private let legacyService: String
    private let currentService: String
    private let account: String
    private let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "AuthKeychainMigration")

    /// - Parameter currentAppID: GOOGLE_APP_ID of the bundled GoogleService-Info.plist.
    init(
        keychain: GenericPasswordKeychain,
        defaults: UserDefaults,
        currentAppID: String,
        legacyAppID: String = Self.legacyAppID,
        account: String = Self.signedInUserAccount
    ) {
        self.keychain = keychain
        self.defaults = defaults
        self.legacyService = Self.keychainService(forAppID: legacyAppID)
        self.currentService = Self.keychainService(forAppID: currentAppID)
        self.account = account
    }

    /// FirebaseAuth's keychain service for an app ID.
    static func keychainService(forAppID appID: String) -> String {
        "firebase_auth_\(appID)"
    }

    @discardableResult
    func runIfNeeded() -> Outcome {
        let outcome = migrate()
        switch outcome {
        case .nothingToMove, .moved, .removedLegacyItem:
            defaults.set(true, forKey: Self.completionKey)
        case .alreadyCompleted, .notNeeded, .deferredUntilUnlocked, .failed:
            break
        }
        log(outcome)
        return outcome
    }

    /// Runs the migration now and, if the keychain is locked, again when protected data
    /// becomes available, until it no longer has to wait.
    ///
    /// When a launch happens before the first unlock (iOS can prewarm the app then),
    /// FirebaseAuth's first keychain read fails too, and Auth reads again once protected
    /// data becomes available. If the session hadn't moved by then, the user would look
    /// signed out until the next launch, and a guest account created meanwhile would
    /// replace the legacy session for good at that launch. Call this before
    /// `FirebaseApp.configure()`: Auth adds its observer only after its own read fails,
    /// and NotificationCenter calls observers in the order they were added (long-standing
    /// behaviour, though not documented), so this moves the session before Auth reads again.
    @discardableResult
    func runIfNeeded(retryingWhenUnlockedOn notificationCenter: NotificationCenter) -> Outcome {
        let outcome = runIfNeeded()
        guard outcome == .deferredUntilUnlocked else { return outcome }
        let unlock = UnlockObservation()
        unlock.observer = notificationCenter.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            // nil runs it on the posting thread, before the post returns.
            queue: nil
        ) { _ in
            // Still locked: keep waiting for the next notification.
            guard runIfNeeded() != .deferredUntilUnlocked, let observer = unlock.observer else { return }
            notificationCenter.removeObserver(observer)
            unlock.observer = nil
        }
        return outcome
    }

    private func migrate() -> Outcome {
        guard !defaults.bool(forKey: Self.completionKey) else { return .alreadyCompleted }
        guard legacyService != currentService else { return .notNeeded }

        let legacy = keychain.statusOfItem(withService: legacyService, account: account)
        guard legacy == errSecSuccess else {
            return legacy == errSecItemNotFound ? .nothingToMove : failure(legacy)
        }

        let current = keychain.statusOfItem(withService: currentService, account: account)
        switch current {
        case errSecItemNotFound:
            let status = keychain.moveItem(account: account, fromService: legacyService, toService: currentService)
            return status == errSecSuccess ? .moved : failure(status)
        case errSecSuccess:
            let status = keychain.deleteItem(withService: legacyService, account: account)
            return status == errSecSuccess || status == errSecItemNotFound ? .removedLegacyItem : failure(status)
        default:
            return failure(current)
        }
    }

    private func failure(_ status: OSStatus) -> Outcome {
        status == errSecInteractionNotAllowed ? .deferredUntilUnlocked : .failed(status)
    }

    private func log(_ outcome: Outcome) {
        switch outcome {
        case .alreadyCompleted, .notNeeded:
            logger.debug("Auth keychain migration not needed")
        case .nothingToMove:
            logger.notice("No legacy Auth session to move")
        case .moved:
            logger.notice("Moved the signed-in user to the current Firebase app's keychain item")
        case .removedLegacyItem:
            logger.notice("Removed the legacy Auth keychain item; the current app already has a session")
        case .deferredUntilUnlocked:
            logger.notice("Keychain is locked; will move the Auth session once it unlocks")
        case .failed(let status):
            logger.error("Auth keychain migration failed with OSStatus \(status); will retry at the next launch")
        }
    }
}

/// The unlock observer, held where its own block can reach it to remove it.
private final class UnlockObservation {
    var observer: NSObjectProtocol?
}

/// `GenericPasswordKeychain` over the SecItem API, with queries shaped like
/// FirebaseAuth's own (AuthKeychainServices.swift `genericPasswordQuery`).
struct SystemKeychain: GenericPasswordKeychain {

    func statusOfItem(withService service: String, account: String) -> OSStatus {
        SecItemCopyMatching(Self.query(service: service, account: account) as CFDictionary, nil)
    }

    func moveItem(account: String, fromService: String, toService: String) -> OSStatus {
        let changes = [kSecAttrService as String: toService]
        return SecItemUpdate(Self.query(service: fromService, account: account) as CFDictionary, changes as CFDictionary)
    }

    func deleteItem(withService service: String, account: String) -> OSStatus {
        SecItemDelete(Self.query(service: service, account: account) as CFDictionary)
    }

    private static func query(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
