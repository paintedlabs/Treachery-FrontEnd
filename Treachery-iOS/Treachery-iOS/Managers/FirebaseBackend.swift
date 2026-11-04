//
//  FirebaseBackend.swift
//  Treachery-iOS
//
//  Chooses and configures the Firebase backend for this launch.
//

import Foundation
import os
import FirebaseAnalytics
import FirebaseAuth
import FirebaseCore
import FirebaseCrashlytics
import FirebaseFirestore
import FirebaseFunctions
import FirebaseMessaging

/// The Firebase backend this launch talks to, decided once before any Firebase use.
enum FirebaseBackend: Equatable {
    /// The shared production project, from GoogleService-Info.plist.
    case production
    #if DEBUG
    /// The repo-root firebase.json emulators on this Mac, under a fake demo project.
    /// Chosen by the `-useEmulators` launch argument, and always for the unit-test
    /// host so hosted tests can never reach production.
    case localEmulators
    #endif

    /// Set while an emulator launch has switched off Analytics, Crashlytics and FCM
    /// auto-init. Those switches persist across launches, so the next production
    /// launch on this install switches them back on.
    static let collectionPausedKey = "localEmulators.collectionPaused"
    static let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "Firebase")

    static func forLaunch(arguments: [String], environment: [String: String]) -> Self {
        #if DEBUG
        if arguments.contains(LocalEmulators.launchArgument) || environment[LocalEmulators.testHostVariable] != nil {
            return .localEmulators
        }
        #endif
        return .production
    }

    /// Configures the default FirebaseApp. Call once, first thing at launch.
    func configure() {
        switch self {
        case .production:
            Self.migrateAuthKeychainIfNeeded()
            FirebaseApp.configure()
            Self.resumeCollectionIfPaused(defaults: .standard)
        #if DEBUG
        case .localEmulators:
            LocalEmulators.configure(defaults: .standard)
        #endif
        }
    }

    private static func migrateAuthKeychainIfNeeded() {
        // Reads the bundled plist without configuring anything.
        guard let currentAppID = FirebaseOptions.defaultOptions()?.googleAppID else { return }
        FirebaseAuthKeychainMigration(keychain: SystemKeychain(), defaults: .standard, currentAppID: currentAppID)
            .runIfNeeded(retryingWhenUnlockedOn: .default)
    }

    /// Switches Analytics, Crashlytics and FCM auto-init back on after an emulator launch.
    /// Compiled into every build: a Release build installed over a Debug build whose last
    /// launch used the emulators (as every hosted unit-test run does) must not keep them off.
    private static func resumeCollectionIfPaused(defaults: UserDefaults) {
        guard defaults.bool(forKey: collectionPausedKey) else { return }
        Analytics.setAnalyticsCollectionEnabled(true)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        Messaging.messaging().isAutoInitEnabled = true
        defaults.removeObject(forKey: collectionPausedKey)
        logger.notice("Resumed Analytics, Crashlytics and FCM auto-init after an emulator launch")
    }
}

#if DEBUG
extension FirebaseBackend {
    /// What the default FirebaseApp was actually configured with, read back from
    /// Firebase (nil before configuration), so hosted tests can check the launch itself.
    static var configuredDefaultApp: (projectID: String?, googleAppID: String, clientID: String?)? {
        guard let options = FirebaseApp.app()?.options else { return nil }
        return (options.projectID, options.googleAppID, options.clientID)
    }
}

/// Wiring for the local emulators. DEBUG only, so Release builds can't reach it.
///
/// Matches the web playtest (Treachery/src/config/firebase.ts and
/// Treachery/scripts/emulators-exec.js): project demo-test, emulators on localhost.
/// The options are fake, so anything not pointed at an emulator fails instead of
/// reaching production, and emulator sessions get their own keychain item.
enum LocalEmulators {
    static let launchArgument = "-useEmulators"
    /// Set by XCTest in the host app of hosted unit tests.
    static let testHostVariable = "XCTestConfigurationFilePath"

    static let projectID = "demo-test"
    /// Fake but well-formed: FirebaseCore refuses a malformed GOOGLE_APP_ID (FIRApp.m `validateAppID`).
    static let googleAppID = "1:123456789012:ios:0123456789abcdef"
    static let gcmSenderID = "123456789012"
    /// Fake but well-formed: FirebaseInstallations, which every launch starts, throws on an
    /// API key that isn't 39 URL-safe characters starting with "A" (FIRInstallations.m
    /// `validateAPIKey`). The web playtest's "demo" would crash the app at launch.
    static let apiKey = "A-demo-key-for-local-firebase-emulators"

    static let host = "localhost"
    // Ports from the repo-root firebase.json.
    static let authPort = 9099
    static let firestorePort = 8087
    static let functionsPort = 5001

    static func configure(defaults: UserDefaults) {
        let options = FirebaseOptions(googleAppID: googleAppID, gcmSenderID: gcmSenderID)
        options.projectID = projectID
        options.apiKey = apiKey
        // The bundled app's CLIENT_ID, used only to pick phone sign-in's callback URL scheme.
        // Without it PhoneAuthProvider falls back to "app-" plus the fake app ID, which
        // Info.plist doesn't register, so Send Code would hit its fatalError
        // (PhoneAuthProvider.swift `init(auth:)` ~L643-664 and ~L107-111). Nothing reaches
        // Google: the simulator skips app verification, so no reCAPTCHA page opens.
        options.clientID = FirebaseOptions.defaultOptions()?.clientID
        FirebaseApp.configure(options: options)

        Auth.auth().useEmulator(withHost: host, port: authPort)

        let firestore = Firestore.firestore()
        let settings = firestore.settings
        settings.host = "\(host):\(firestorePort)"
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        firestore.settings = settings

        Functions.functions().useEmulator(withHost: host, port: functionsPort)

        Analytics.setAnalyticsCollectionEnabled(false)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        Messaging.messaging().isAutoInitEnabled = false
        defaults.set(true, forKey: FirebaseBackend.collectionPausedKey)

        FirebaseBackend.logger.notice(
            """
            Using the local Firebase emulators for project \(projectID, privacy: .public) on \(host, privacy: .public): \
            auth \(authPort), firestore \(firestorePort), functions \(functionsPort)
            """
        )
    }
}
#endif
