//
//  HomeView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import SwiftUI

// MARK: - Navigation Destinations

/// All navigation destinations managed by the root NavigationStack.
/// Using a single enum lets `path.removeLast(path.count)` pop to root reliably.
enum AppDestination: Hashable {
    case createGame
    case joinGame
    case lobby(gameId: String, isHost: Bool)
    case gameBoard(gameId: String)
    case gameOver(gameId: String)
    case profile
    case friends
    case gameHistory
}

struct HomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var path = NavigationPath()
    #if DEBUG
    @ObservedObject private var devSettings = DevSettings.shared
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 24) {
                #if DEBUG
                // Dev mode banner
                if devSettings.devModeEnabled {
                    HStack(spacing: 6) {
                        Image(systemName: "hammer.fill")
                            .font(.caption)
                        Text("DEV MODE")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.orange)
                    .clipShape(Capsule())
                }
                #endif

                Spacer()

                Text("Treachery")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)

                NavigationLink("Create Game", value: AppDestination.createGame)
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Create a new game")
                    .accessibilityHint("Set up a new Treachery game as host")

                NavigationLink("Join Game", value: AppDestination.joinGame)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Join an existing game")
                    .accessibilityHint("Enter a game code to join")

                Spacer()

                // Bottom navigation
                HStack(spacing: 24) {
                    NavigationLink(value: AppDestination.gameHistory) {
                        VStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                            Text("History")
                                .font(.caption)
                        }
                    }
                    .accessibilityLabel("Game history")

                    NavigationLink(value: AppDestination.friends) {
                        VStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                            Text("Friends")
                                .font(.caption)
                        }
                    }
                    .accessibilityLabel("Friends list")

                    NavigationLink(value: AppDestination.profile) {
                        VStack(spacing: 4) {
                            Image(systemName: "person.circle.fill")
                            Text("Profile")
                                .font(.caption)
                        }
                    }
                    .accessibilityLabel("Your profile")

                    #if DEBUG
                    Button {
                        devSettings.devModeEnabled.toggle()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: devSettings.devModeEnabled ? "hammer.fill" : "hammer")
                                .foregroundStyle(devSettings.devModeEnabled ? .orange : .secondary)
                            Text("Dev")
                                .font(.caption)
                                .foregroundStyle(devSettings.devModeEnabled ? .orange : .secondary)
                        }
                    }
                    .accessibilityLabel("Toggle dev mode")
                    .accessibilityValue(devSettings.devModeEnabled ? "Enabled" : "Disabled")
                    #endif
                }
                .padding(.bottom)
            }
            .padding()
            .navigationTitle("Home")
            .navigationDestination(for: AppDestination.self) { destination in
                switch destination {
                case .createGame:
                    CreateGameView(navigationPath: $path)
                case .joinGame:
                    JoinGameView(navigationPath: $path)
                case .lobby(let gameId, let isHost):
                    LobbyView(gameId: gameId, isHost: isHost, navigationPath: $path)
                case .gameBoard(let gameId):
                    GameBoardView(gameId: gameId, navigationPath: $path)
                case .gameOver(let gameId):
                    GameOverView(gameId: gameId, navigationPath: $path)
                case .profile:
                    ProfileView()
                case .friends:
                    FriendsListView()
                case .gameHistory:
                    GameHistoryView()
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    HomeView()
        .environmentObject(AuthViewModel())
}
#endif
