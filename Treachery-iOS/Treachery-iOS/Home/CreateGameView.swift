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

    @State private var gameMode: GameMode = .treachery
    @State private var useOwnDeck = false
    @State private var startingLife = 40
    @State private var isCreating = false
    @State private var errorMessage: String?

    private let firestoreManager = FirestoreManager()

    /// Max players is determined by game mode — no user input needed.
    private var maxPlayers: Int {
        gameMode.includesTreachery ? 8 : 12
    }

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            ScrollView {
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

                    // Game Mode selector
                    VStack(spacing: 8) {
                        MtgSectionHeader(title: "Game Mode")
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Picker("Game Mode", selection: $gameMode) {
                            ForEach(GameMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal)

                    if gameMode.includesPlanechase {
                        Toggle("I have my own planar deck", isOn: $useOwnDeck)
                            .foregroundStyle(Color.mtgTextPrimary)
                            .tint(Color.mtgGold)
                            .padding(.horizontal)
                    }

                    // Game settings card
                    VStack(spacing: 20) {
                        MtgSectionHeader(title: "Game Settings")

                        OrnateDivider()

                        Stepper("Starting Life: \(startingLife)", value: $startingLife, in: 20...60, step: 5)
                            .foregroundStyle(Color.mtgTextPrimary)
                            .accessibilityValue("\(startingLife) life")
                    }
                    .padding(16)
                    .mtgCardFrame()

                    if let error = errorMessage {
                        MtgErrorBanner(message: error)
                    }

                    Button {
                        Task { await createGame() }
                    } label: {
                        if isCreating {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Color.mtgBackground)
                                Text("Creating...")
                            }
                        } else {
                            Text("Create Game")
                        }
                    }
                    .buttonStyle(MtgPrimaryButtonStyle(isDisabled: isCreating))
                    .disabled(isCreating)
                    .accessibilityLabel(isCreating ? "Creating game" : "Create game")
                }
                .padding()
            }
        }
        .navigationTitle("Create Game")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { AnalyticsService.trackScreen("CreateGame") }
        .onChange(of: gameMode) { _, _ in
            // Reset own deck toggle when planechase is disabled
            if !gameMode.includesPlanechase {
                useOwnDeck = false
            }
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
                gameMode: gameMode,
                maxPlayers: maxPlayers,
                startingLife: startingLife,
                winningTeam: nil,
                playerIds: [userId],
                createdAt: Date(),
                lastActivityAt: Date(),
                planechase: gameMode.includesPlanechase ? PlanechaseState(
                    useOwnDeck: useOwnDeck,
                    currentPlaneId: nil,
                    usedPlaneIds: [],
                    lastDieRollerId: nil,
                    dieRollCount: 0
                ) : nil
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

            AnalyticsService.trackEvent("create_game", params: [
                "game_mode": gameMode.rawValue
            ])
            navigationPath.append(AppDestination.lobby(gameId: game.id, isHost: true))
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

#if DEBUG
#Preview {
    NavigationStack {
        CreateGameView(navigationPath: .preview)
    }
    .environmentObject(AuthViewModel())
}
#endif
