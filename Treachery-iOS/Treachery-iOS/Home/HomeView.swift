//
//  HomeView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import SwiftUI

// MARK: - Navigation Destinations

/// Game-flow destinations managed by the Home tab's NavigationStack.
/// Using a single enum lets `path.removeLast(path.count)` pop to root reliably.
enum AppDestination: Hashable {
    case createGame
    case joinGame
    case lobby(gameId: String, isHost: Bool)
    case gameBoard(gameId: String)
    case gameOver(gameId: String)
    #if DEBUG
    case devTestAbilities
    #endif
}

// MARK: - Tab Selection

enum AppTab: Hashable {
    case home
    case history
    case friends
    case profile
}

// MARK: - Root Tab View

struct HomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var selectedTab: AppTab = .home

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.mtgSurface)

        let normalAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(Color.mtgTextSecondary)
        ]
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(Color.mtgGold)
        ]

        appearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttributes
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(Color.mtgTextSecondary)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttributes
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color.mtgGold)

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeTab()
                .tabItem {
                    Label("Play", systemImage: "gamecontroller.fill")
                }
                .tag(AppTab.home)

            NavigationStack {
                GameHistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock.fill")
            }
            .tag(AppTab.history)

            NavigationStack {
                FriendsListView()
            }
            .tabItem {
                Label("Friends", systemImage: "person.2.fill")
            }
            .tag(AppTab.friends)

            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("Profile", systemImage: "person.circle.fill")
            }
            .tag(AppTab.profile)
        }
    }
}

// MARK: - Home Tab

/// The main Play tab — contains the game flow NavigationStack.
private struct HomeTab: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var path = NavigationPath()
    @StateObject private var viewModel = HomeViewModel()

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
                        endRadius: 500
                    )
                }
                .ignoresSafeArea()

                VStack(spacing: 24) {
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
                    if let game = viewModel.activeGame {
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

                    #if DEBUG
                    NavigationLink(value: AppDestination.devTestAbilities) {
                        HStack(spacing: 6) {
                            Image(systemName: "hammer.fill")
                            Text("Dev: Test Abilities")
                        }
                    }
                    .buttonStyle(MtgSecondaryButtonStyle())
                    .padding(.horizontal)
                    #endif

                    Spacer()
                }
                .padding(.horizontal)
            }
            .navigationBarHidden(true)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { AnalyticsService.trackScreen("Home") }
            .task(id: path.count) {
                // Re-check every time we return to the home screen (path becomes empty)
                guard path.isEmpty,
                      let userId = authViewModel.currentUserId else { return }
                await viewModel.checkForActiveGame(userId: userId)
            }
            .navigationDestination(for: AppDestination.self) { destination in
                switch destination {
                case .createGame:
                    CreateGameView(navigationPath: $path)
                case .joinGame:
                    JoinGameView(navigationPath: $path)
                case .lobby(let gameId, let isHost):
                    LobbyView(gameId: gameId, isHost: isHost, navigationPath: $path)
                        .toolbar(.hidden, for: .tabBar)
                case .gameBoard(let gameId):
                    GameBoardView(gameId: gameId, currentUserId: authViewModel.currentUserId, navigationPath: $path)
                        .toolbar(.hidden, for: .tabBar)
                case .gameOver(let gameId):
                    GameOverView(gameId: gameId, navigationPath: $path)
                        .toolbar(.hidden, for: .tabBar)
                #if DEBUG
                case .devTestAbilities:
                    AbilityTestingView()
                        .toolbar(.hidden, for: .tabBar)
                #endif
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
