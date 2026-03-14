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
    @State private var joinedGame: Game?

    private let firestoreManager = FirestoreManager()

    var body: some View {
        VStack(spacing: 24) {
            Text("Enter the 4-character game code")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("ABCD", text: $gameCode)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .font(.title.monospaced())
                .multilineTextAlignment(.center)
                .accessibilityLabel("Game code")
                .accessibilityHint("Enter the 4-character code to join a game")
                .onChange(of: gameCode) { _, newValue in
                    gameCode = String(newValue.uppercased().prefix(4))
                }

            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Error: \(error)")
            }

            Button {
                Task { await joinGame() }
            } label: {
                if isJoining {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text("Joining...")
                    }
                } else {
                    Text("Join Game")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(gameCode.count < 4 || isJoining)
            .accessibilityLabel(isJoining ? "Joining game" : "Join game")

            Spacer()
        }
        .padding()
        .navigationTitle("Join Game")
        .navigationDestination(item: $joinedGame) { game in
            LobbyView(gameId: game.id, isHost: false, navigationPath: $navigationPath)
        }
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
                joinedGame = game
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

            joinedGame = game
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
