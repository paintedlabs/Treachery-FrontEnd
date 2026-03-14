//
//  CreateGameView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/13/26.
//

import SwiftUI

struct CreateGameView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Binding var navigationPath: NavigationPath

    @State private var maxPlayers = Role.minimumPlayerCount
    @State private var startingLife = 40
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var createdGame: Game?

    private let firestoreManager = FirestoreManager()

    var body: some View {
        VStack(spacing: 24) {
            #if DEBUG
            if DevSettings.shared.devModeEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "hammer.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Dev Mode: 1-player minimum")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.1))
                .clipShape(Capsule())
            }
            #endif

            Stepper("Players: \(maxPlayers)", value: $maxPlayers, in: Role.minimumPlayerCount...8)
                .accessibilityValue("\(maxPlayers) players")

            Stepper("Starting Life: \(startingLife)", value: $startingLife, in: 20...60, step: 5)
                .accessibilityValue("\(startingLife) life")

            // Role distribution preview
            let dist = Role.distribution(forPlayerCount: maxPlayers)
            HStack(spacing: 12) {
                RoleBadge(count: dist.leaders, role: .leader)
                RoleBadge(count: dist.guardians, role: .guardian)
                RoleBadge(count: dist.assassins, role: .assassin)
                RoleBadge(count: dist.traitors, role: .traitor)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Role distribution: \(dist.leaders) leaders, \(dist.guardians) guardians, \(dist.assassins) assassins, \(dist.traitors) traitors")

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
                Task { await createGame() }
            } label: {
                if isCreating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text("Creating...")
                    }
                } else {
                    Text("Create Game")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCreating)
            .accessibilityLabel(isCreating ? "Creating game" : "Create game")

            Spacer()
        }
        .padding()
        .navigationTitle("Create Game")
        .navigationDestination(item: $createdGame) { game in
            LobbyView(gameId: game.id, isHost: true, navigationPath: $navigationPath)
        }
    }

    private func createGame() async {
        guard let userId = authViewModel.currentUserId else { return }
        isCreating = true
        errorMessage = nil

        do {
            let code = try await generateUniqueCode()
            let game = Game(
                id: UUID().uuidString,
                code: code,
                hostId: userId,
                state: .waiting,
                maxPlayers: maxPlayers,
                startingLife: startingLife,
                winningTeam: nil,
                playerIds: [userId],
                createdAt: Date()
            )
            try await firestoreManager.createGame(game)

            // Add host as first player
            let user = try await firestoreManager.getUser(id: userId)
            let player = Player(
                id: UUID().uuidString,
                orderId: 0,
                userId: userId,
                displayName: user?.displayName ?? "Host",
                role: nil,
                identityCardId: nil,
                lifeTotal: startingLife,
                isEliminated: false,
                isUnveiled: false,
                joinedAt: Date()
            )
            try await firestoreManager.addPlayer(player, toGame: game.id)

            createdGame = game
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }

    private func generateUniqueCode() async throws -> String {
        // Charset excludes ambiguous characters: I, O, 0, 1
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        for _ in 0..<10 {
            let code = String((0..<4).map { _ in characters.randomElement()! })
            let existing = try await firestoreManager.getGame(byCode: code)
            if existing == nil {
                return code
            }
        }
        throw GameError.codeGenerationFailed
    }
}

// MARK: - Role Badge

private struct RoleBadge: View {
    let count: Int
    let role: Role

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(role.color)
            Text(role.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) \(role.displayName)")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        CreateGameView(navigationPath: .preview)
    }
    .environmentObject(AuthViewModel())
}
#endif
