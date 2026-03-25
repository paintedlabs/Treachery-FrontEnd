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
    @State private var activeGame: Game?
    private let firestoreManager = FirestoreManager()
    #if DEBUG
    @ObservedObject private var devSettings = DevSettings.shared
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                // Radial gradient background
                ZStack {
                    Color.mtgBackground
                    RadialGradient(
                        colors: [
                            Color(hex: "1e1735").opacity(0.8),
                            Color.mtgBackground
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: UIScreen.main.bounds.height * 0.6
                    )
                }
                .ignoresSafeArea()

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

                    // Title treatment with subtle glow
                    VStack(spacing: 8) {
                        Text("Treachery")
                            .font(.system(size: 42, weight: .bold, design: .serif))
                            .mtgGoldShimmer()
                            .shadow(color: Color.mtgGold.opacity(0.4), radius: 16, x: 0, y: 0)
                            .shadow(color: Color.mtgGold.opacity(0.2), radius: 32, x: 0, y: 0)
                            .accessibilityAddTraits(.isHeader)

                        Text("A Game of Hidden Allegiance")
                            .font(.system(.caption, design: .serif))
                            .foregroundStyle(Color.mtgTextSecondary)
                            .opacity(0.8)

                        OrnateDivider()
                            .padding(.horizontal, 40)
                    }

                    Spacer()
                        .frame(height: 20)

                    // Rejoin active game banner
                    if let game = activeGame {
                        Button {
                            if game.state == .inProgress {
                                path.append(AppDestination.gameBoard(gameId: game.id))
                            } else {
                                let isHost = game.hostId == authViewModel.currentUserId
                                path.append(AppDestination.lobby(gameId: game.id, isHost: isHost))
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "gamecontroller.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.mtgGoldBright)
                                    .frame(width: 40, height: 40)
                                    .background(Color.mtgGold.opacity(0.15))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(game.state == .inProgress ? "Game in Progress" : "Game Waiting")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.mtgGoldBright)
                                    Text("Tap to rejoin")
                                        .font(.caption)
                                        .foregroundStyle(Color.mtgTextSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Color.mtgGold)
                            }
                            .padding(12)
                            .mtgCardFrame()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                        .accessibilityLabel("Rejoin \(game.state == .inProgress ? "active" : "waiting") game")
                    }

                    // Main actions
                    NavigationLink(value: AppDestination.createGame) {
                        Text("Create Game")
                    }
                    .buttonStyle(MtgPrimaryButtonStyle())
                    .accessibilityLabel("Create a new game")
                    .accessibilityHint("Set up a new Treachery game as host")
                    .padding(.horizontal)

                    NavigationLink(value: AppDestination.joinGame) {
                        Text("Join Game")
                    }
                    .buttonStyle(MtgSecondaryButtonStyle())
                    .accessibilityLabel("Join an existing game")
                    .accessibilityHint("Enter a game code to join")
                    .padding(.horizontal)

                    Spacer()
                        .frame(height: 16)

                    Spacer()

                    // Bottom navigation with tab bar surface
                    HStack(spacing: 24) {
                        NavigationLink(value: AppDestination.gameHistory) {
                            VStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.title3)
                                Text("History")
                                    .font(.caption)
                            }
                            .foregroundStyle(Color.mtgTextSecondary)
                        }
                        .accessibilityLabel("Game history")

                        NavigationLink(value: AppDestination.friends) {
                            VStack(spacing: 4) {
                                Image(systemName: "person.2.fill")
                                    .font(.title3)
                                Text("Friends")
                                    .font(.caption)
                            }
                            .foregroundStyle(Color.mtgTextSecondary)
                        }
                        .accessibilityLabel("Friends list")

                        NavigationLink(value: AppDestination.profile) {
                            VStack(spacing: 4) {
                                Image(systemName: "person.circle.fill")
                                    .font(.title3)
                                Text("Profile")
                                    .font(.caption)
                            }
                            .foregroundStyle(Color.mtgTextSecondary)
                        }
                        .accessibilityLabel("Your profile")

                        #if DEBUG
                        Button {
                            devSettings.devModeEnabled.toggle()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: devSettings.devModeEnabled ? "hammer.fill" : "hammer")
                                    .font(.title3)
                                    .foregroundStyle(devSettings.devModeEnabled ? .orange : Color.mtgTextSecondary)
                                Text("Dev")
                                    .font(.caption)
                                    .foregroundStyle(devSettings.devModeEnabled ? .orange : Color.mtgTextSecondary)
                            }
                        }
                        .accessibilityLabel("Toggle dev mode")
                        .accessibilityValue(devSettings.devModeEnabled ? "Enabled" : "Disabled")
                        #endif
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
                    .background(
                        Color.mtgSurface.opacity(0.85)
                            .overlay(
                                Rectangle()
                                    .fill(Color.mtgDivider)
                                    .frame(height: 1),
                                alignment: .top
                            )
                    )
                }
                .padding(.horizontal)
            }
            .navigationTitle("Home")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task(id: path.count) {
                // Re-check every time we return to the home screen (path becomes empty)
                guard path.isEmpty,
                      let userId = authViewModel.currentUserId else { return }
                do {
                    activeGame = try await firestoreManager.getActiveGame(forUserId: userId)
                } catch {
                    activeGame = nil
                }
            }
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
