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
        VStack(spacing: 24) {
            if viewModel.players.isEmpty {
                Spacer()
                ProgressView("Loading results...")
                Spacer()
            } else {
                Spacer()

                // Winner announcement
                if let winningTeam = viewModel.winningTeam {
                    VStack(spacing: 8) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(winningTeam.color)

                        Text("Game Over")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        HStack(spacing: 8) {
                            Circle()
                                .fill(winningTeam.color)
                                .frame(width: 16, height: 16)
                            Text("\(winningTeam.displayName) Wins!")
                                .font(.title)
                                .fontWeight(.semibold)
                                .foregroundStyle(winningTeam.color)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(winningTeam.displayName) team wins")
                    }
                }

                // All players revealed
                VStack(spacing: 0) {
                    ForEach(viewModel.players) { player in
                        HStack {
                            Circle()
                                .fill(player.role?.color ?? .gray)
                                .frame(width: 12, height: 12)

                            Text(player.displayName)
                                .fontWeight(.medium)

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(player.role?.displayName ?? "Unknown")
                                    .font(.subheadline)
                                    .foregroundStyle(player.role?.color ?? .secondary)

                                if let card = viewModel.identityCard(for: player) {
                                    Text(card.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if player.isEliminated {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                                    .padding(.leading, 4)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(player.displayName), \(player.role?.displayName ?? "Unknown")\(player.isEliminated ? ", eliminated" : "")")

                        if player.id != viewModel.players.last?.id {
                            Divider()
                                .padding(.horizontal)
                        }
                    }
                }
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                Spacer()

                // Return home
                Button("Return to Home") {
                    navigationPath.removeLast(navigationPath.count)
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom)
                .accessibilityLabel("Return to home screen")
            }
        }
        .navigationTitle("Results")
        .navigationBarBackButtonHidden(true)
        .onAppear {
            viewModel.currentUserId = authViewModel.currentUserId
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
