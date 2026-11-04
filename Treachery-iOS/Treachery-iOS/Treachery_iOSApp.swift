//
//  Treachery_iOSApp.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 9/10/24.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

@main
struct Treachery_iOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - AppDelegate
class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    /// Keeps this device's FCM token registered to whoever is signed in. Created once
    /// Firebase is configured, and kept for the app's lifetime.
    private var pushNotificationRegistrar: PushNotificationRegistrar?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let processInfo = ProcessInfo.processInfo
        FirebaseBackend.forLaunch(arguments: processInfo.arguments, environment: processInfo.environment)
            .configure()

        #if targetEnvironment(simulator)
        Auth.auth().settings?.isAppVerificationDisabledForTesting = true
        #endif

        // Push notification setup. Permission is asked for after sign-in, by the registrar.
        UNUserNotificationCenter.current().delegate = self
        let registrar = PushNotificationRegistrar(
            signedInUser: AuthStateUserObserver(authManager: FirebaseManager()),
            profiles: FirestoreUserProfileObserver(firestore: Firestore.firestore()),
            tokens: MessagingTokenProvider(messaging: Messaging.messaging()),
            cloudFunctions: CloudFunctions(),
            notificationAuthorization: UserNotificationAuthorization(center: UNUserNotificationCenter.current()),
            notificationCenter: .default,
            defaults: .standard
        )
        registrar.start()
        pushNotificationRegistrar = registrar
        Messaging.messaging().delegate = self

        // Register for remote notifications (required for phone auth + FCM)
        application.registerForRemoteNotifications()

        return true
    }

    // MARK: - Orientation Lock (portrait only on iPhone)

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .portrait
    }

    // MARK: - Phone Auth APNs Support

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        if Auth.auth().canHandleNotification(userInfo) {
            return .noData
        }
        return .newData
    }

    // MARK: - reCAPTCHA Fallback URL Handling

    // No app delegate `open url` handler: with the scene manifest, UIKit delivers opened
    // URLs to the scene, where FirebaseAuth's own scene-delegate hook handles them.

    // MARK: - FCM Token

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        pushNotificationRegistrar?.registrationTokenDidChange(fcmToken)
    }

    // MARK: - Foreground Notification Display

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
}
