//
//  HomeView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import SwiftUI

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

                NavigationLink("Create Game") {
                    CreateGameView(navigationPath: $path)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Create a new game")
                .accessibilityHint("Set up a new Treachery game as host")

                NavigationLink("Join Game") {
                    JoinGameView(navigationPath: $path)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Join an existing game")
                .accessibilityHint("Enter a game code to join")

                Spacer()

                // Bottom navigation
                HStack(spacing: 24) {
                    NavigationLink {
                        GameHistoryView()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                            Text("History")
                                .font(.caption)
                        }
                    }
                    .accessibilityLabel("Game history")

                    NavigationLink {
                        FriendsListView()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                            Text("Friends")
                                .font(.caption)
                        }
                    }
                    .accessibilityLabel("Friends list")

                    NavigationLink {
                        ProfileView()
                    } label: {
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
        }
    }
}

#if DEBUG
#Preview {
    HomeView()
        .environmentObject(AuthViewModel())
}
#endif
