//
//  Treachery_iOSApp.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 9/10/24.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth

@main
struct Treachery_iOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
        }
    }
}

// MARK: - AppDelegate
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()

        #if DEBUG
        Auth.auth().settings?.isAppVerificationDisabledForTesting = true
        #endif

        // Register for remote notifications (required for phone auth silent push)
        application.registerForRemoteNotifications()

        return true
    }

    // MARK: - Phone Auth APNs Support

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
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

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if Auth.auth().canHandle(url) {
            return true
        }
        return false
    }
}
