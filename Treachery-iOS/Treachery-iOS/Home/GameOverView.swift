//
//  GameOverView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import SwiftUI

struct GameOverView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: GameBoardViewModel
    @Binding var navigationPath: NavigationPath

    init(gameId: String, navigationPath: Binding<NavigationPath>) {
        _viewModel = StateObject(wrappedValue: GameBoardViewModel(gameId: gameId))
        _navigationPath = navigationPath
    }

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                if viewModel.players.isEmpty {
                    Spacer()
                    ProgressView("Loading results...")
                        .tint(Color.mtgGold)
                        .foregroundStyle(Color.mtgTextSecondary)
                    Spacer()
                } else {
                    let isTreacheryMode = viewModel.game?.gameMode.includesTreachery ?? true

                    Spacer()

                    if isTreacheryMode {
                        // Winner announcement (treachery modes only)
                        if let winningTeam = viewModel.winningTeam {
                            VStack(spacing: 12) {
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: 48))
                                    .foregroundStyle(winningTeam.color)

                                Text("Game Over")
                                    .font(.system(size: 36, weight: .bold, design: .serif))
                                    .foregroundStyle(Color.mtgTextPrimary)

                                OrnateDivider()
                                    .padding(.horizontal, 40)

                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(winningTeam.color)
                                        .frame(width: 16, height: 16)
                                    Text("\(winningTeam.displayName) Wins!")
                                        .font(.system(.title, design: .serif))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(winningTeam.color)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(winningTeam.displayName) team wins")
                            }
                        }

                        // All players revealed (treachery modes only)
                        VStack(spacing: 0) {
                            ForEach(viewModel.players) { player in
                                HStack {
                                    Circle()
                                        .fill(player.role?.color ?? .gray)
                                        .frame(width: 12, height: 12)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(player.displayName)
                                            .fontWeight(.medium)
                                            .foregroundStyle(Color.mtgTextPrimary)
                                        if let commander = player.commanderName, !commander.isEmpty {
                                            Text(commander)
                                                .font(.caption2)
                                                .foregroundStyle(Color.mtgGold)
                                        }
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(player.role?.displayName ?? "Unknown")
                                            .font(.subheadline)
                                            .foregroundStyle(player.role?.color ?? Color.mtgTextSecondary)

                                        if let card = viewModel.identityCard(for: player) {
                                            Text(card.name)
                                                .font(.caption)
                                                .foregroundStyle(Color.mtgTextSecondary)
                                        }
                                    }

                                    if player.isEliminated {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(Color.mtgError)
                                            .font(.caption)
                                            .padding(.leading, 4)
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 16)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(player.displayName), \(player.role?.displayName ?? "Unknown")\(player.isEliminated ? ", eliminated" : "")")

                                if player.id != viewModel.players.last?.id {
                                    Rectangle()
                                        .fill(Color.mtgDivider)
                                        .frame(height: 1)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                        .mtgCardFrame()
                        .padding(.horizontal)
                    } else {
                        // Non-treachery game over: simple summary
                        VStack(spacing: 12) {
                            Image(systemName: "flag.checkered")
                                .font(.system(size: 48))
                                .foregroundStyle(Color.mtgGold)

                            Text("Game Over")
                                .font(.system(size: 36, weight: .bold, design: .serif))
                                .foregroundStyle(Color.mtgTextPrimary)

                            OrnateDivider()
                                .padding(.horizontal, 40)

                            if let mode = viewModel.game?.gameMode {
                                Text(mode.displayName)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.mtgBackground)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.mtgGold)
                                    .clipShape(Capsule())
                            }

                            Text("\(viewModel.players.count) player\(viewModel.players.count == 1 ? "" : "s")")
                                .font(.subheadline)
                                .foregroundStyle(Color.mtgTextSecondary)
                        }

                        // Player list without roles
                        VStack(spacing: 0) {
                            ForEach(viewModel.players) { player in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(player.displayName)
                                            .fontWeight(.medium)
                                            .foregroundStyle(Color.mtgTextPrimary)
                                        if let commander = player.commanderName, !commander.isEmpty {
                                            Text(commander)
                                                .font(.caption2)
                                                .foregroundStyle(Color.mtgGold)
                                        }
                                    }

                                    Spacer()

                                    if player.isEliminated {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(Color.mtgError)
                                            .font(.caption)
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 16)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(player.displayName)\(player.isEliminated ? ", eliminated" : "")")

                                if player.id != viewModel.players.last?.id {
                                    Rectangle()
                                        .fill(Color.mtgDivider)
                                        .frame(height: 1)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                        .mtgCardFrame()
                        .padding(.horizontal)
                    }

                    Spacer()

                    // Return home
                    Button("Return to Home") {
                        navigationPath.removeLast(navigationPath.count)
                    }
                    .buttonStyle(MtgPrimaryButtonStyle())
                    .padding(.horizontal)
                    .padding(.bottom)
                    .accessibilityLabel("Return to home screen")
                }
            }
        }
        .navigationTitle("Results")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            viewModel.currentUserId = authViewModel.currentUserId
        }
        .task {
            await updateDeckLastPlayed()
        }
    }

    private func updateDeckLastPlayed() async {
        guard let userId = authViewModel.currentUserId else { return }
        // Wait for players to load
        while viewModel.players.isEmpty {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let myPlayer = viewModel.players.first(where: { $0.userId == userId }),
              let deckId = myPlayer.deckId else { return }

        let firestoreManager = FirestoreManager()
        if var deck = try? await firestoreManager.getDeck(id: deckId, userId: userId) {
            deck.lastPlayedAt = Date()
            try? await firestoreManager.updateDeck(deck)
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        GameOverView(gameId: "preview-game", navigationPath: .preview)
    }
    .environmentObject(AuthViewModel())
}
#endif
