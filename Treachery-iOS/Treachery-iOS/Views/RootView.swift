//
//  RootView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch authViewModel.authState {
            case .loading:
                ZStack {
                    Color.mtgBackground.ignoresSafeArea()
                    VStack(spacing: 16) {
                        Text("Treachery")
                            .font(.system(size: 36, weight: .bold, design: .serif))
                            .foregroundStyle(Color.mtgGoldBright)
                        ProgressView()
                            .tint(Color.mtgGold)
                    }
                }
            case .authenticated:
                // The name prompt covers the tabs rather than replacing them:
                // a profile set up late, by a retry, can need a name while a
                // game is open, and replacing the tabs would close it.
                ZStack {
                    HomeView()
                        .accessibilityHidden(authViewModel.isNewUser)
                    if authViewModel.isNewUser {
                        OnboardingFlow()
                    }
                }
            case .unauthenticated:
                NavigationStack {
                    LoginView()
                }
            }
        }
        .preferredColorScheme(.dark)
        // Back in the app, the connection may be back too, so a postponed
        // profile setup tries again now rather than at its next retry.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                authViewModel.retryPostponedProfileSetup()
            }
        }
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
