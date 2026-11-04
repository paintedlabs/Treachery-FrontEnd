//
//  GameStatusView.swift
//  Treachery-iOS
//
//  Full-screen states for the lobby, board and Game Over when there is no
//  game to show yet, or any more. Those screens hide the back button and the
//  tab bar, so every state here offers a way home.
//

import Accessibility
import SwiftUI

/// The spinner a game screen shows while its first snapshots arrive, with a
/// way home in case they never do.
struct GameLoadingView: View {
    let message: String
    let onGoHome: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            MtgLoadingView(message: message)
            Button(action: onGoHome) {
                Text("Back to Home")
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(Color.mtgGold)
            .padding(.horizontal)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// A message for a game that is gone, has finished, couldn't be loaded, or
/// needs a newer version of the app. Offers one more action, such as Try
/// Again, when there's something better to do than leave.
struct GameStatusView: View {
    /// The button above Back to Home.
    struct Action {
        let title: String
        let perform: () -> Void

        /// For a failure that trying again can fix.
        static func tryAgain(_ perform: @escaping () -> Void) -> Self {
            Self(title: "Try Again", perform: perform)
        }
    }

    let systemImage: String
    var tint: Color = .mtgGold
    let title: String
    let message: String
    var action: Action?
    let onGoHome: () -> Void

    var body: some View {
        // Centred when it fits, scrollable when large text makes it taller
        // than the screen, so the buttons can always be reached.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.largeTitle)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.system(.title2, design: .serif))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.mtgTextPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Color.mtgTextSecondary)
                        .multilineTextAlignment(.center)
                    actions
                        .padding(.top)
                        .padding(.horizontal, 24)
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear {
            // This replaces the screen's content in place, so have VoiceOver
            // start again from the top instead of staying silent.
            AccessibilityNotification.ScreenChanged().post()
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(MtgPrimaryButtonStyle())
                Button("Back to Home", action: onGoHome)
                    .buttonStyle(MtgSecondaryButtonStyle())
            } else {
                Button("Back to Home", action: onGoHome)
                    .buttonStyle(MtgPrimaryButtonStyle())
            }
        }
        // Labels wrap at the largest text sizes; keep them centred.
        .multilineTextAlignment(.center)
    }
}

extension GameStatusView {
    /// For a game this build can't play: its state or mode is one it doesn't
    /// know, or its data can't be decoded.
    static func needsNewerVersion(onGoHome: @escaping () -> Void) -> GameStatusView {
        GameStatusView(
            systemImage: "arrow.down.app.fill",
            title: "Update Required",
            message: "This game needs a newer version of Treachery. Update the app to keep playing.",
            onGoHome: onGoHome
        )
    }

    /// For a game the server won't show the user any more because they're
    /// no longer in it. There's nothing to try again.
    static func notInGame(onGoHome: @escaping () -> Void) -> GameStatusView {
        GameStatusView(
            systemImage: "person.crop.circle.badge.xmark",
            title: "Not in This Game",
            message: "You're no longer in this game. You can create or join another game from Home.",
            onGoHome: onGoHome
        )
    }
}

#if DEBUG
#Preview("Loading") {
    ZStack {
        Color.mtgBackground.ignoresSafeArea()
        GameLoadingView(message: "Loading lobby...", onGoHome: {})
    }
}

#Preview("Failed") {
    ZStack {
        Color.mtgBackground.ignoresSafeArea()
        GameStatusView(
            systemImage: "exclamationmark.triangle.fill",
            title: "Couldn't Load the Lobby",
            message: "Check your connection and try again.",
            action: .tryAgain {},
            onGoHome: {}
        )
    }
}

#Preview("Needs Newer Version") {
    ZStack {
        Color.mtgBackground.ignoresSafeArea()
        GameStatusView.needsNewerVersion(onGoHome: {})
    }
    .dynamicTypeSize(.accessibility5)
}

#Preview("Not in This Game") {
    ZStack {
        Color.mtgBackground.ignoresSafeArea()
        GameStatusView.notInGame(onGoHome: {})
    }
}
#endif
