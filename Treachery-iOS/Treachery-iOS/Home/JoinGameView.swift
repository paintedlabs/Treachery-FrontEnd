//
//  JoinGameView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/13/26.
//

import SwiftUI

struct JoinGameView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Binding var navigationPath: NavigationPath

    @State private var gameCode = ""
    @State private var isJoining = false
    @State private var errorMessage: String?

    private let firestoreManager = FirestoreManager()

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 20)

                // Game code entry card
                VStack(spacing: 16) {
                    MtgSectionHeader(title: "Enter Game Code")

                    OrnateDivider()

                    Text("Enter the 4-character game code")
                        .font(.subheadline)
                        .foregroundStyle(Color.mtgTextSecondary)

                    TextField("ABCD", text: $gameCode)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .foregroundStyle(Color.mtgGoldBright)
                        .background(Color.mtgCardElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.mtgGold, lineWidth: 1.5)
                        )
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("Game code")
                        .accessibilityHint("Enter the 4-character code to join a game")
                        .onChange(of: gameCode) { _, newValue in
                            gameCode = String(newValue.uppercased().prefix(4))
                        }
                }
                .padding(20)
                .mtgCardFrame()

                if let error = errorMessage {
                    MtgErrorBanner(message: error)
                }

                Button {
                    Task { await joinGame() }
                } label: {
                    if isJoining {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.mtgBackground)
                            Text("Joining...")
                        }
                    } else {
                        Text("Join Game")
                    }
                }
                .buttonStyle(MtgPrimaryButtonStyle(isDisabled: gameCode.count < 4 || isJoining))
                .disabled(gameCode.count < 4 || isJoining)
                .accessibilityLabel(isJoining ? "Joining game" : "Join game")

                Spacer()
            }
            .padding()
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func joinGame() async {
        guard let userId = authViewModel.currentUserId else { return }
        isJoining = true
        errorMessage = nil

        do {
            // Find game by code
            guard let game = try await firestoreManager.getGame(byCode: gameCode) else {
                throw GameError.gameNotFound
            }

            // Validate game state
            guard game.state == .waiting else {
                throw GameError.gameAlreadyStarted
            }

            // Check if game is full
            let existingPlayers = try await firestoreManager.getPlayers(gameId: game.id)
            guard existingPlayers.count < game.maxPlayers else {
                throw GameError.gameFull
            }

            // Check if user is already in the game
            if existingPlayers.contains(where: { $0.userId == userId }) {
                navigationPath.append(AppDestination.lobby(gameId: game.id, isHost: false))
                isJoining = false
                return
            }

            // Add player
            let user = try await firestoreManager.getUser(id: userId)
            let player = Player(
                id: UUID().uuidString,
                orderId: existingPlayers.count,
                userId: userId,
                displayName: user?.displayName ?? "Player",
                role: nil,
                identityCardId: nil,
                lifeTotal: game.startingLife,
                isEliminated: false,
                isUnveiled: false,
                joinedAt: Date()
            )
            try await firestoreManager.addPlayer(player, toGame: game.id)

            // Add user to game's playerIds for history queries
            try await firestoreManager.addPlayerIdToGame(gameId: game.id, userId: userId)

            navigationPath.append(AppDestination.lobby(gameId: game.id, isHost: false))
        } catch {
            errorMessage = error.localizedDescription
        }
        isJoining = false
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        JoinGameView(navigationPath: .preview)
    }
    .environmentObject(AuthViewModel())
}
#endif
