//
//  RootView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    // Built here rather than in Treachery_iOSApp, the composition root, only
    // because that file was being changed in parallel when the gate landed.
    // Moving it there would also let the app hold off start-up work, such as
    // the auth listener, until the gate allows.
    @StateObject private var versionGate = VersionGateViewModel.live()

    var body: some View {
        // The version gate comes before the auth switch, so a build that must
        // update never reaches sign-in or the home screen.
        VersionGateView(model: versionGate) {
            switch authViewModel.authState {
            case .loading:
                LaunchSplashView()
            case .authenticated:
                if authViewModel.isNewUser {
                    OnboardingFlow()
                } else {
                    HomeView()
                }
            case .unauthenticated:
                NavigationStack {
                    LoginView()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Onboarding Flow

private struct OnboardingFlow: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var step = 0

    var body: some View {
        Group {
            if step == 0 {
                DisplayNamePromptView {
                    step = 1
                }
            } else {
                WelcomeView {
                    authViewModel.completeOnboarding()
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    RootView()
        .environmentObject(AuthViewModel())
}
#endif
