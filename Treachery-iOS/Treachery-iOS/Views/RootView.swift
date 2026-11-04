//
//  RootView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

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
                // game is open, and replacing the tabs would close it. So
                // the tabs stay as they were, and Profile and Friends load
                // again once the setup is finished.
                ZStack {
                    HomeView()
                        .accessibilityHidden(authViewModel.isNewUser)
                    if authViewModel.isNewUser {
                        OnboardingFlow()
                            // Modal, as AccountDeletionOverlay is: VoiceOver
                            // stays in the prompt, out of the tabs beneath.
                            .accessibilityElement(children: .contain)
                            .accessibilityAddTraits(.isModal)
                            // A field focused in the tabs, such as Friends'
                            // search, would keep the keyboard, and what's
                            // typed would go where no one can see it.
                            .onAppear {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
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

    @Environment(\.scenePhase) private var scenePhase
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
