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

    @State private var trophyScale: CGFloat = 0.3
    @State private var contentOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            // Dynamic radial glow based on winning team color
            if let winningTeam = viewModel.winningTeam {
                RadialGradient(
                    colors: [
                        winningTeam.color.opacity(0.15),
                        Color.mtgBackground
                    ],
                    center: .top,
                    startRadius: 20,
                    endRadius: 420
                )
                .ignoresSafeArea()
            } else {
                RadialGradient(
                    colors: [
                        Color(hex: "1e1735").opacity(0.6),
                        Color.mtgBackground
                    ],
                    center: .top,
                    startRadius: 20,
                    endRadius: 420
                )
                .ignoresSafeArea()
            }

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
                            VStack(spacing: 16) {
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: 56))
                                    .foregroundStyle(winningTeam.color)
                                    .shadow(color: winningTeam.color.opacity(0.5), radius: 16, x: 0, y: 0)
                                    .shadow(color: winningTeam.color.opacity(0.3), radius: 32, x: 0, y: 0)
                                    .scaleEffect(trophyScale)

                                Text("Game Over")
                                    .font(.system(size: 40, weight: .bold, design: .serif))
                                    .foregroundStyle(Color.mtgTextPrimary)

                                OrnateDivider()
                                    .padding(.horizontal, 40)

                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(winningTeam.color)
                                        .frame(width: 16, height: 16)
                                        .shadow(color: winningTeam.color.opacity(0.6), radius: 6)
                                    Text("\(winningTeam.displayName) Wins!")
                                        .font(.system(.title, design: .serif))
                                        .fontWeight(.bold)
                                        .foregroundStyle(winningTeam.color)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(winningTeam.displayName) team wins")
                            }
                            .opacity(contentOpacity)
                        }

                        // All players revealed (treachery modes only)
                        VStack(spacing: 0) {
                            ForEach(viewModel.players) { player in
                                HStack {
                                    // Left accent bar for player color
                                    if let hex = player.playerColor {
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(Color(hex: hex))
                                            .frame(width: 3)
                                            .padding(.vertical, 2)
                                            .padding(.trailing, 4)
                                    }

                                    Circle()
                                        .fill(player.role?.color ?? .gray)
                                        .frame(width: 12, height: 12)
                                        .shadow(color: (player.role?.color ?? .gray).opacity(0.4), radius: 4)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(player.displayName)
                                            .fontWeight(.medium)
                                            .foregroundStyle(Color.mtgTextPrimary)

                                        if let commanderName = player.commanderName, !commanderName.isEmpty {
                                            Text(commanderName)
                                                .font(.system(.caption, design: .serif))
                                                .italic()
                                                .foregroundStyle(Color.mtgTextSecondary)
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
                                .font(.system(size: 56))
                                .foregroundStyle(Color.mtgGold)
                                .shadow(color: Color.mtgGold.opacity(0.4), radius: 16, x: 0, y: 0)
                                .scaleEffect(trophyScale)

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
                                    // Left accent bar for player color
                                    if let hex = player.playerColor {
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(Color(hex: hex))
                                            .frame(width: 3)
                                            .padding(.vertical, 2)
                                            .padding(.trailing, 4)
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(player.displayName)
                                            .fontWeight(.medium)
                                            .foregroundStyle(Color.mtgTextPrimary)

                                        if let commanderName = player.commanderName, !commanderName.isEmpty {
                                            Text(commanderName)
                                                .font(.system(.caption, design: .serif))
                                                .italic()
                                                .foregroundStyle(Color.mtgTextSecondary)
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
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.2)) {
                trophyScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                contentOpacity = 1.0
            }
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
