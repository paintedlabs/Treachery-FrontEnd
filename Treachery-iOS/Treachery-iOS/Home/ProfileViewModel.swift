//
//  ProfileViewModel.swift
//  Treachery-iOS
//

import Foundation

struct GameStats {
    let totalGames: Int
    let wins: Int
    let losses: Int
    let roleBreakdown: [Role: Int]

    var winRateText: String {
        guard totalGames > 0 else { return "--" }
        let rate = Double(wins) / Double(totalGames) * 100
        return "\(Int(rate))%"
    }
}

@MainActor
final class ProfileViewModel: ObservableObject {

    // MARK: - Published State

    @Published var user: TreacheryUser?
    @Published var gameStats: GameStats?
    @Published var editedName = ""
    @Published var isEditingName = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    // MARK: - Properties

    private var userId: String?
    private let firestoreManager: FirestoreManaging

    // MARK: - Init

    init(firestoreManager: FirestoreManaging = FirestoreManager()) {
        self.firestoreManager = firestoreManager
    }

    // MARK: - Data Loading

    func loadData(userId: String) async {
        self.userId = userId
        errorMessage = nil

        do {
            async let userTask = firestoreManager.getUser(id: userId)
            async let gamesTask = firestoreManager.getFinishedGames(forUserId: userId)

            user = try await userTask
            let games = try await gamesTask

            await calculateStats(games: games)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Name Editing

    func startEditing() {
        editedName = user?.displayName ?? ""
        isEditingName = true
    }

    func saveName() async {
        guard var updatedUser = user, userId != nil else { return }
        guard !editedName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSaving = true
        errorMessage = nil

        updatedUser.displayName = editedName.trimmingCharacters(in: .whitespaces)
        do {
            try await firestoreManager.updateUser(updatedUser)
            user = updatedUser
            isEditingName = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    // MARK: - Stats Calculation

    private func calculateStats(games: [Game]) async {
        guard let userId else { return }
        var wins = 0
        var losses = 0
        var roleBreakdown: [Role: Int] = [:]

        for game in games {
            if let players = try? await firestoreManager.getPlayers(gameId: game.id),
               let myPlayer = players.first(where: { $0.userId == userId }),
               let myRole = myPlayer.role {

                roleBreakdown[myRole, default: 0] += 1

                if let winTeamString = game.winningTeam,
                   let winRole = Role(rawValue: winTeamString) {
                    let didWin: Bool
                    if winRole == .leader {
                        didWin = myRole == .leader || myRole == .guardian
                    } else {
                        didWin = myRole == winRole
                    }
                    if didWin {
                        wins += 1
                    } else {
                        losses += 1
                    }
                }
            }
        }

        gameStats = GameStats(
            totalGames: games.count,
            wins: wins,
            losses: losses,
            roleBreakdown: roleBreakdown
        )
    }
}
