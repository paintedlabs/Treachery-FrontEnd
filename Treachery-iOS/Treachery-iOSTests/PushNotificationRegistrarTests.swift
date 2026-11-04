import Testing
import Foundation
import UIKit
import UserNotifications
@testable import Treachery_iOS

@MainActor
final class PushNotificationRegistrarTests {

    private let user = FakeSignedInUser()
    private let profiles = FakeUserProfiles()
    private let log = CallLog()
    private let tokens: FakePushTokens
    private let permission: FakeNotificationPermission
    private let cloudFunctions = MockCloudFunctions()
    private let notificationCenter = NotificationCenter()
    private let suiteName = "PushNotificationRegistrarTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        tokens = FakePushTokens(log: log)
        permission = FakeNotificationPermission(log: log)
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Helpers

    private func makeRegistrar(observing observedUser: FakeSignedInUser? = nil) -> PushNotificationRegistrar {
        let registrar = PushNotificationRegistrar(
            signedInUser: observedUser ?? user,
            profiles: profiles,
            tokens: tokens,
            cloudFunctions: cloudFunctions,
            notificationAuthorization: permission,
            notificationCenter: notificationCenter,
            defaults: defaults
        )
        registrar.start()
        return registrar
    }

    /// Posts UIKit's activation notification, then lets the registrar finish.
    private func appBecomesActive(_ registrar: PushNotificationRegistrar) async {
        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await registrar.waitUntilIdle()
    }

    // MARK: - Launch

    @Test func signedOutLaunchLeavesTheTokenAlone() async {
        let registrar = makeRegistrar()
        user.emit(nil)
        await registrar.waitUntilIdle()

        #expect(log.calls.isEmpty)
        #expect(cloudFunctions.registerFcmTokenCalls.isEmpty)
    }

    @Test func restoredSessionRegistersTheCurrentToken() async {
        let registrar = makeRegistrar()
        user.emit("u1")
        await registrar.waitUntilIdle()

        #expect(cloudFunctions.registerFcmTokenCalls == ["token-1"])
        #expect(tokens.deleteCount == 0)
    }

    // MARK: - Public profile

    /// registerFcmToken merge-writes users/{uid}. Called before the app creates the
    /// profile, it creates an empty one that the rules then stop the app from filling in.
    @Test func nothingIsRegisteredUntilTheServerHasTheProfile() async {
        permission.status = .notDetermined
        profiles.missing = ["u1"]
        let registrar = makeRegistrar()
        user.emit("u1")
        registrar.registrationTokenDidChange("token-1")
        await registrar.waitUntilIdle()

        #expect(log.calls.isEmpty)
        #expect(cloudFunctions.registerFcmTokenCalls.isEmpty)

        profiles.create("u1")
        await registrar.waitUntilIdle()

        #expect(log.calls == ["requestAuthorization", "currentToken"])
        #expect(cloudFunctions.registerFcmTokenCalls == ["token-1"])
        #expect(profiles.listener(for: "u1")?.removeCalled == true)
    }

    @Test func signingOutWhileWaitingForTheProfileStopsWaiting() async {
        profiles.missing = ["u1"]
        let registrar = makeRegistrar()
        await registrar.process(user, emitting: ["u1", nil])
        #expect(profiles.listener(for: "u1")?.removeCalled == true)

        profiles.create("u1")
        await registrar.waitUntilIdle()

        // A previous launch may have registered this device to u1, so the token still goes.
        #expect(log.calls == ["deleteToken"])
        #expect(cloudFunctions.registerFcmTokenCalls.isEmpty)
    }

    // MARK: - Permission

    @Test func signInAsksForUndecidedPermissionBeforeRegistering() async {
        permission.status = .notDetermined
        let registrar = makeRegistrar()
        user.emit(nil)
        user.emit("u1")
        await registrar.waitUntilIdle()

        #expect(log.calls == ["requestAuthorization", "currentToken"])
        #expect(cloudFunctions.registerFcmTokenCalls == ["token-1"])
    }

    @Test func decidedPermissionIsNotAskedForAgain() async {
        permission.status = .denied
        let registrar = makeRegistrar()
        user.emit("u1")
        await registrar.waitUntilIdle()

        #expect(permission.requestCount == 0)
        // Still registered, so turning notifications on in Settings later just works.
        #expect(cloudFunctions.registerFcmTokenCalls == ["token-1"])
    }

    @Test func permissionIsAskedForAtMostOncePerLaunch() async {
        permission.status = .notDetermined
        permission.staysUndecided = true
        let registrar = makeRegistrar()
        await registrar.process(user, emitting: ["u1", nil, "u2"])

        #expect(permission.requestCount == 1)
        #expect(cloudFunctions.registerFcmTokenCalls == ["token-1", "token-2"])
    }

    // MARK: - Token refresh

    @Test func refreshWhileSignedInRegistersTheNewToken() async {
        let registrar = makeRegistrar()
        user.emit("u1")
        registrar.registrationTokenDidChange("token-9")
        await registrar.waitUntilIdle()

        #expect(cloudFunctions.registerFcmTokenCalls == ["token-1", "token-9"])
    }

    @Test func refreshWhileSignedOutIsIgnored() async {
        let registrar = makeRegistrar()
        user.emit(nil)
        registrar.registrationTokenDidChange("token-9")
        await registrar.waitUntilIdle()

        #expect(cloudFunctions.registerFcmTokenCalls.isEmpty)
    }

    @Test func sameUserAndTokenAreRegisteredOnce() async {
        let registrar = makeRegistrar()
        user.emit("u1")
        registrar.registrationTokenDidChange("token-1")
        await registrar.waitUntilIdle()
        registrar.registrationTokenDidChange("token-1")
        await registrar.waitUntilIdle()

        #expect(cloudFunctions.registerFcmTokenCalls == ["token-1"])
    }

    // MARK: - Sign-out and account switch

    @Test func signOutDeletesTheTokenAndTheNextSignInRegistersAFreshOne() async {
        let registrar = makeRegistrar()
        await registrar.process(user, emitting: ["u1", nil])
        #expect(tokens.deleteCount == 1)

        await registrar.process(user, emitting: ["u2"])

        #expect(log.calls == ["currentToken", "deleteToken", "currentToken"])
        #expect(cloudFunctions.registerFcmTokenCalls == ["token-1", "token-2"])
    }

    @Test func switchingAccountsDeletesTheTokenBeforeRegisteringTheNextAccount() async {
        let registrar = makeRegistrar()
        await registrar.process(user, emitting: ["u1", "u2"])

        #expect(log.calls == ["currentToken", "deleteToken", "currentToken"])
        #expect(cloudFunctions.registerFcmTokenCalls == ["token-1", "token-2"])
    }

    @Test func signOutBeforeAQueuedRegistrationRunsCancelsIt() async {
        let registrar = makeRegistrar()
        user.emit("u1")
        user.emit(nil)
        await registrar.waitUntilIdle()

        #expect(log.calls == ["deleteToken"])
        #expect(cloudFunctions.registerFcmTokenCalls.isEmpty)
    }

    // MARK: - Failures and retries

    @Test func failedRegistrationIsRetriedOnTheNextRefresh() async {
        cloudFunctions.errorToThrow = TestError.offline
        let registrar = makeRegistrar()
        user.emit("u1")
        await registrar.waitUntilIdle()
        #expect(cloudFunctions.registerFcmTokenCalls.isEmpty)

        cloudFunctions.errorToThrow = nil
        registrar.registrationTokenDidChange("token-1")
        await registrar.waitUntilIdle()

        #expect(cloudFunctions.registerFcmTokenCalls == ["token-1"])
    }

    @Test func tokenDeliveredBeforeTheSessionIsUsedWhenFetchingFails() async {
        // At launch, FCM's callback can beat the auth callback, and fetching
        // fails until APNs answers.
        tokens.currentTokenError = TestError.noAPNsToken
        let registrar = makeRegistrar()
        registrar.registrationTokenDidChange("token-1")
        user.emit("u1")
        await registrar.waitUntilIdle()

        #expect(cloudFunctions.registerFcmTokenCalls == ["token-1"])
    }

    @Test func tokenIsRegisteredWhenFCMDeliversItAfterSignIn() async {
        tokens.currentTokenError = TestError.noAPNsToken
        let registrar = makeRegistrar()
        user.emit("u1")
        await registrar.waitUntilIdle()
        #expect(cloudFunctions.registerFcmTokenCalls.isEmpty)

        registrar.registrationTokenDidChange("token-7")
        await registrar.waitUntilIdle()

        #expect(cloudFunctions.registerFcmTokenCalls == ["token-7"])
    }

    @Test func failedDeletionIsRetriedAtTheNextLaunch() async {
        tokens.deleteError = TestError.offline
        let firstLaunch = makeRegistrar()
        await firstLaunch.process(user, emitting: ["u1", nil])
        #expect(tokens.deleteCount == 0)

        tokens.deleteError = nil
        let relaunchedUser = FakeSignedInUser()
        let nextLaunch = makeRegistrar(observing: relaunchedUser)
        await nextLaunch.process(relaunchedUser, emitting: [nil])

        #expect(tokens.deleteCount == 1)
        #expect(log.calls == ["currentToken", "deleteToken", "deleteToken"])
    }

    @Test func failedDeletionIsRetriedBeforeTheNextAccountRegisters() async {
        tokens.deleteError = TestError.offline
        let registrar = makeRegistrar()
        await registrar.process(user, emitting: ["u1", nil])

        tokens.deleteError = nil
        await registrar.process(user, emitting: ["u2"])

        #expect(tokens.deleteCount == 1)
        #expect(cloudFunctions.registerFcmTokenCalls == ["token-1", "token-2"])
    }

    @Test func failedDeletionIsRetriedWhenTheAppBecomesActive() async {
        tokens.deleteError = TestError.offline
        let registrar = makeRegistrar()
        await registrar.process(user, emitting: ["u1", nil])
        #expect(tokens.deleteCount == 0)

        tokens.deleteError = nil
        await appBecomesActive(registrar)
        #expect(tokens.deleteCount == 1)

        // Nothing pending any more.
        await appBecomesActive(registrar)
        #expect(log.calls == ["currentToken", "deleteToken", "deleteToken"])
    }

    // MARK: - Lifetime

    @Test func releasingTheRegistrarStopsObservingSignIns() async {
        weak var released: PushNotificationRegistrar?
        do {
            let registrar = makeRegistrar()
            released = registrar
            user.emit("u1")
            await registrar.waitUntilIdle()
        }

        #expect(released == nil)
        #expect(user.listener.removeCalled)
    }
}

/// Which `users/{uid}` snapshots count as the server having the profile. Registering
/// on any other would let registerFcmToken create an empty profile on the server.
struct FirestoreUserProfileObserverTests {

    @Test func serverConfirmedProfileCounts() {
        #expect(FirestoreUserProfileObserver.serverHasProfile(exists: true, isFromCache: false, hasPendingWrites: false))
    }

    /// The persistent cache can still hold a profile the server has since deleted.
    @Test(arguments: [false, true]) func cachedProfileDoesNotCount(hasPendingWrites: Bool) {
        #expect(!FirestoreUserProfileObserver.serverHasProfile(exists: true, isFromCache: true, hasPendingWrites: hasPendingWrites))
    }

    /// The app's own profile write, before the server has committed it.
    @Test(arguments: [false, true]) func profileWithAnUncommittedWriteDoesNotCount(isFromCache: Bool) {
        #expect(!FirestoreUserProfileObserver.serverHasProfile(exists: true, isFromCache: isFromCache, hasPendingWrites: true))
    }

    @Test(arguments: [false, true], [false, true]) func missingProfileNeverCounts(isFromCache: Bool, hasPendingWrites: Bool) {
        #expect(!FirestoreUserProfileObserver.serverHasProfile(exists: false, isFromCache: isFromCache, hasPendingWrites: hasPendingWrites))
    }
}

// MARK: - Fakes

private extension PushNotificationRegistrar {
    /// Emits each sign-in change and lets the registrar finish before the next,
    /// the way a person signs in and out.
    func process(_ user: FakeSignedInUser, emitting uids: [String?]) async {
        for uid in uids {
            user.emit(uid)
            await waitUntilIdle()
        }
    }
}

private enum TestError: Error {
    case offline
    case noAPNsToken
}

/// The calls the registrar makes on the fakes below, in order.
private final class CallLog {
    var calls: [String] = []
}

/// Drives sign-in changes by hand.
private final class FakeSignedInUser: SignedInUserObserving {
    let listener = MockListenerCancellable()
    private var onChange: (@MainActor (String?) -> Void)?

    func observeSignedInUser(_ onChange: @escaping @MainActor (String?) -> Void) -> ListenerCancellable {
        self.onChange = onChange
        return listener
    }

    @MainActor
    func emit(_ uid: String?) {
        onChange?(uid)
    }
}

/// Stands in for the users/{uid} listener. Every account already has a profile unless
/// it is listed in `missing`; an existing profile is reported from inside the call.
private final class FakeUserProfiles: UserProfileObserving {
    var missing: Set<String> = []
    private var listeners: [String: MockListenerCancellable] = [:]
    private var onExists: [String: @MainActor () -> Void] = [:]

    func observeProfileExists(forUser uid: String, _ onExists: @escaping @MainActor () -> Void) -> ListenerCancellable {
        let listener = MockListenerCancellable()
        listeners[uid] = listener
        if missing.contains(uid) {
            self.onExists[uid] = onExists
        } else {
            MainActor.assumeIsolated { onExists() }
        }
        return listener
    }

    func listener(for uid: String) -> MockListenerCancellable? {
        listeners[uid]
    }

    /// The app's profile write for `uid` reaches the server.
    @MainActor
    func create(_ uid: String) {
        missing.remove(uid)
        guard let listener = listeners[uid], !listener.removeCalled else { return }
        onExists[uid]?()
    }
}

/// Stands in for FCM: hands out the current token, and a new one after each deletion.
private final class FakePushTokens: PushTokenProviding {
    var currentTokenError: Error?
    var deleteError: Error?
    private(set) var deleteCount = 0
    private let log: CallLog

    init(log: CallLog) {
        self.log = log
    }

    func currentToken() async throws -> String {
        log.calls.append("currentToken")
        if let currentTokenError { throw currentTokenError }
        return "token-\(deleteCount + 1)"
    }

    func deleteToken() async throws {
        log.calls.append("deleteToken")
        if let deleteError { throw deleteError }
        deleteCount += 1
    }
}

private final class FakeNotificationPermission: NotificationAuthorizing {
    var status = UNAuthorizationStatus.authorized
    /// Leaves the status undecided after a request, as when the app closes with the prompt up.
    var staysUndecided = false
    private(set) var requestCount = 0
    private let log: CallLog

    init(log: CallLog) {
        self.log = log
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization() async throws -> Bool {
        log.calls.append("requestAuthorization")
        requestCount += 1
        if !staysUndecided {
            status = .authorized
        }
        return !staysUndecided
    }
}
