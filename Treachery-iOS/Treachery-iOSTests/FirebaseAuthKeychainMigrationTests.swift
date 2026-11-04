import Testing
import Foundation
import Security
import UIKit
@testable import Treachery_iOS

final class FirebaseAuthKeychainMigrationTests {

    private static let currentAppID = "1:573413045061:ios:a6cb88e8259bfcd790442c"
    private static let account = FirebaseAuthKeychainMigration.signedInUserAccount
    private static let legacyKey = FakeKeychain.Key(
        service: FirebaseAuthKeychainMigration.keychainService(forAppID: FirebaseAuthKeychainMigration.legacyAppID),
        account: account
    )
    private static let currentKey = FakeKeychain.Key(
        service: FirebaseAuthKeychainMigration.keychainService(forAppID: currentAppID),
        account: account
    )
    /// Items the migration must never touch: the legacy service's other account (Auth's
    /// phone-auth app credential), the same account under another app, and another app's item.
    private static let neighbors: [FakeKeychain.Key: Data] = [
        .init(service: legacyKey.service, account: "firebase_auth_1_app_credentials"): Data("credential".utf8),
        .init(service: "firebase_auth_1:573413045061:ios:0000000000000000", account: account): Data("other-app".utf8),
        .init(service: "com.example.unrelated", account: "someone"): Data("unrelated".utf8),
    ]

    private let keychain = FakeKeychain()
    private let suiteName = "FirebaseAuthKeychainMigrationTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        keychain.items = Self.neighbors
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Helpers

    private func makeMigration(currentAppID: String? = nil) -> FirebaseAuthKeychainMigration {
        FirebaseAuthKeychainMigration(
            keychain: keychain,
            defaults: defaults,
            currentAppID: currentAppID ?? Self.currentAppID
        )
    }

    private func runMigration(currentAppID: String? = nil) -> FirebaseAuthKeychainMigration.Outcome {
        makeMigration(currentAppID: currentAppID).runIfNeeded()
    }

    private var isRecordedComplete: Bool {
        defaults.bool(forKey: FirebaseAuthKeychainMigration.completionKey)
    }

    /// Posts the unlock notification with the completion record cleared. A completed
    /// migration returns before touching the keychain, which would hide an observer left
    /// registered; without the record, any observer still there reaches the keychain.
    private func postUnlockWithoutCompletionRecord(on notificationCenter: NotificationCenter) {
        defaults.removeObject(forKey: FirebaseAuthKeychainMigration.completionKey)
        notificationCenter.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
    }

    /// The keychain minus the neighbors, after checking the neighbors are untouched.
    private func sessionItems() -> [FakeKeychain.Key: Data] {
        for (key, data) in Self.neighbors {
            #expect(keychain.items[key] == data, "touched \(key.service) / \(key.account)")
        }
        return keychain.items.filter { Self.neighbors[$0.key] == nil }
    }

    // MARK: - Decisions

    @Test func movesTheLegacySessionWhenOnlyItExists() {
        keychain.items[Self.legacyKey] = Data("legacy-user".utf8)

        #expect(runMigration() == .moved)
        #expect(sessionItems() == [Self.currentKey: Data("legacy-user".utf8)])
        #expect(isRecordedComplete)
    }

    @Test func keepsTheCurrentSessionAndRemovesTheLegacyOneWhenBothExist() {
        keychain.items[Self.legacyKey] = Data("legacy-user".utf8)
        keychain.items[Self.currentKey] = Data("current-user".utf8)

        #expect(runMigration() == .removedLegacyItem)
        #expect(sessionItems() == [Self.currentKey: Data("current-user".utf8)])
        #expect(isRecordedComplete)
    }

    @Test func recordsCompletionWhenThereIsNoSession() {
        #expect(runMigration() == .nothingToMove)
        #expect(sessionItems().isEmpty)
        #expect(isRecordedComplete)
    }

    @Test func lockedKeychainIsRetriedAtTheNextLaunch() {
        keychain.items[Self.legacyKey] = Data("legacy-user".utf8)
        keychain.failure = errSecInteractionNotAllowed

        #expect(runMigration() == .deferredUntilUnlocked)
        #expect(sessionItems() == [Self.legacyKey: Data("legacy-user".utf8)])
        #expect(!isRecordedComplete)

        keychain.failure = nil
        #expect(runMigration() == .moved)
        #expect(sessionItems() == [Self.currentKey: Data("legacy-user".utf8)])
        #expect(isRecordedComplete)
    }

    /// FirebaseAuth reads the keychain again when protected data becomes available, so the
    /// session has to move in the same launch or the user looks signed out until the next.
    @Test func lockedKeychainIsRetriedWhenItUnlocks() {
        let notificationCenter = NotificationCenter()
        keychain.items[Self.legacyKey] = Data("legacy-user".utf8)
        keychain.failure = errSecInteractionNotAllowed

        #expect(makeMigration().runIfNeeded(retryingWhenUnlockedOn: notificationCenter) == .deferredUntilUnlocked)
        #expect(!isRecordedComplete)

        // Still locked when the notification arrives: it keeps waiting.
        notificationCenter.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        #expect(sessionItems() == [Self.legacyKey: Data("legacy-user".utf8)])
        #expect(!isRecordedComplete)

        keychain.failure = nil
        notificationCenter.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        #expect(sessionItems() == [Self.currentKey: Data("legacy-user".utf8)])
        #expect(isRecordedComplete)

        // Done, so it stops observing.
        let callsAfterRetry = keychain.callCount
        postUnlockWithoutCompletionRecord(on: notificationCenter)
        #expect(keychain.callCount == callsAfterRetry)
    }

    @Test func unlockedKeychainIsNotRetried() {
        let notificationCenter = NotificationCenter()
        keychain.items[Self.legacyKey] = Data("legacy-user".utf8)

        #expect(makeMigration().runIfNeeded(retryingWhenUnlockedOn: notificationCenter) == .moved)
        let callsAfterRun = keychain.callCount
        postUnlockWithoutCompletionRecord(on: notificationCenter)
        #expect(keychain.callCount == callsAfterRun)
    }

    @Test func completedMigrationNeverTouchesTheKeychainAgain() {
        defaults.set(true, forKey: FirebaseAuthKeychainMigration.completionKey)
        keychain.items[Self.legacyKey] = Data("legacy-user".utf8)

        #expect(runMigration() == .alreadyCompleted)
        #expect(keychain.callCount == 0)
        #expect(sessionItems() == [Self.legacyKey: Data("legacy-user".utf8)])
    }

    @Test func unexpectedKeychainErrorIsRetriedAtTheNextLaunch() {
        keychain.items[Self.legacyKey] = Data("legacy-user".utf8)
        keychain.failure = errSecMissingEntitlement

        #expect(runMigration() == .failed(errSecMissingEntitlement))
        #expect(sessionItems() == [Self.legacyKey: Data("legacy-user".utf8)])
        #expect(!isRecordedComplete)
    }

    @Test func bundledLegacyAppIDNeedsNoMigration() {
        keychain.items[Self.legacyKey] = Data("legacy-user".utf8)

        #expect(runMigration(currentAppID: FirebaseAuthKeychainMigration.legacyAppID) == .notNeeded)
        #expect(sessionItems() == [Self.legacyKey: Data("legacy-user".utf8)])
        #expect(!isRecordedComplete)
    }

    // MARK: - Real keychain

    /// Writes an item the way FirebaseAuth 11.15.0 writes the signed-in user, moves it
    /// through the real keychain, and reads it back with FirebaseAuth's exact query.
    /// Uses unique test-only services and accounts, removed afterwards.
    ///
    /// Runs only in a signed test host, such as Xcode's own test runs. The gate script and
    /// CI build the host with CODE_SIGNING_ALLOWED=NO, so it is skipped there.
    @Test(.enabled(if: TestHostKeychain.isAvailable, "the test host has no keychain entitlement (built with CODE_SIGNING_ALLOWED=NO, as in CI)"))
    func movedItemIsFoundByFirebaseAuthsOwnQuery() throws {
        let id = UUID().uuidString
        let legacyAppID = "test-legacy-\(id)"
        let currentAppID = "test-current-\(id)"
        let account = "firebase_auth_1_test-\(id)_firebase_user"
        // Auth's phone-auth credential item (AuthAppCredentialManager), under the same
        // service. The services are unique to this run, so the real account name is safe.
        let neighborAccount = "firebase_auth_1_app_credentials"
        let legacyService = FirebaseAuthKeychainMigration.keychainService(forAppID: legacyAppID)
        let currentService = FirebaseAuthKeychainMigration.keychainService(forAppID: currentAppID)
        defer {
            SecItemDelete(firebaseAuthQuery(service: legacyService, account: account) as CFDictionary)
            SecItemDelete(firebaseAuthQuery(service: currentService, account: account) as CFDictionary)
            SecItemDelete(firebaseAuthQuery(service: legacyService, account: neighborAccount) as CFDictionary)
            SecItemDelete(firebaseAuthQuery(service: currentService, account: neighborAccount) as CFDictionary)
        }

        // AuthKeychainServices.setItemLegacy: the query plus the data and this accessibility.
        let archivedUser = Data("archived-user-\(id)".utf8)
        try addFirebaseAuthItem(archivedUser, service: legacyService, account: account)
        let credential = Data("credential-\(id)".utf8)
        try addFirebaseAuthItem(credential, service: legacyService, account: neighborAccount)

        let migration = FirebaseAuthKeychainMigration(
            keychain: SystemKeychain(),
            defaults: defaults,
            currentAppID: currentAppID,
            legacyAppID: legacyAppID,
            account: account
        )
        #expect(migration.runIfNeeded() == .moved)

        // AuthKeychainServices.data(forKey:) → getItemLegacy(query:).
        var query = firebaseAuthQuery(service: currentService, account: account)
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = 2
        var result: AnyObject?
        let readStatus = SecItemCopyMatching(query as CFDictionary, &result)
        try #require(readStatus == errSecSuccess, "SecItemCopyMatching failed with OSStatus \(readStatus)")
        let items = try #require(result as? [[String: Any]])
        #expect(items.count == 1)
        #expect(items.first?[kSecValueData as String] as? Data == archivedUser)
        #expect(items.first?[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)

        let legacyStatus = SecItemCopyMatching(firebaseAuthQuery(service: legacyService, account: account) as CFDictionary, nil)
        #expect(legacyStatus == errSecItemNotFound)

        var neighborQuery = firebaseAuthQuery(service: legacyService, account: neighborAccount)
        neighborQuery[kSecReturnData as String] = true
        var neighbor: AnyObject?
        #expect(SecItemCopyMatching(neighborQuery as CFDictionary, &neighbor) == errSecSuccess)
        #expect(neighbor as? Data == credential)
        let movedNeighbor = SecItemCopyMatching(firebaseAuthQuery(service: currentService, account: neighborAccount) as CFDictionary, nil)
        #expect(movedNeighbor == errSecItemNotFound)
    }

    private func addFirebaseAuthItem(_ data: Data, service: String, account: String) throws {
        var item = firebaseAuthQuery(service: service, account: account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        try #require(status == errSecSuccess, "SecItemAdd failed with OSStatus \(status)")
    }

    /// FirebaseAuth 11.15.0's query (AuthKeychainServices.swift `genericPasswordQuery`).
    private func firebaseAuthQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}

// MARK: - Fakes

/// An unsigned test host (CODE_SIGNING_ALLOWED=NO) has no application identifier, so
/// every keychain call fails with errSecMissingEntitlement. A signed host can use it.
private enum TestHostKeychain {
    static var isAvailable: Bool {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "FirebaseAuthKeychainMigrationTests.probe",
            kSecUseDataProtectionKeychain as String: true,
        ]
        return SecItemCopyMatching(probe as CFDictionary, nil) != errSecMissingEntitlement
    }
}

/// In-memory generic-password items, keyed by service and account.
private final class FakeKeychain: GenericPasswordKeychain {
    struct Key: Hashable {
        let service: String
        let account: String
    }

    var items: [Key: Data] = [:]
    /// When set, every call fails with it, as a locked keychain does.
    var failure: OSStatus?
    private(set) var callCount = 0

    func statusOfItem(withService service: String, account: String) -> OSStatus {
        callCount += 1
        if let failure { return failure }
        return items[Key(service: service, account: account)] == nil ? errSecItemNotFound : errSecSuccess
    }

    func moveItem(account: String, fromService: String, toService: String) -> OSStatus {
        callCount += 1
        if let failure { return failure }
        let source = Key(service: fromService, account: account)
        let destination = Key(service: toService, account: account)
        guard let data = items[source] else { return errSecItemNotFound }
        guard items[destination] == nil else { return errSecDuplicateItem }
        items[source] = nil
        items[destination] = data
        return errSecSuccess
    }

    func deleteItem(withService service: String, account: String) -> OSStatus {
        callCount += 1
        if let failure { return failure }
        return items.removeValue(forKey: Key(service: service, account: account)) == nil ? errSecItemNotFound : errSecSuccess
    }
}
