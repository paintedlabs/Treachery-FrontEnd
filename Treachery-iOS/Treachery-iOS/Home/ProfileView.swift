//
//  ProfileView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var user: TreacheryUser?
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var gameStats: GameStats?

    private let firestoreManager = FirestoreManager()

    var body: some View {
        List {
            // Profile info
            Section("Profile") {
                if let user = user {
                    HStack {
                        Text("Display Name")
                        Spacer()
                        if isEditingName {
                            TextField("Name", text: $editedName)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.words)
                        } else {
                            Text(user.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let email = user.email {
                        HStack {
                            Text("Email")
                            Spacer()
                            Text(email)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let phone = user.phoneNumber {
                        HStack {
                            Text("Phone")
                            Spacer()
                            Text(phone)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Member Since")
                        Spacer()
                        Text(user.createdAt, style: .date)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }

            // Game stats
            Section("Game Stats") {
                if let stats = gameStats {
                    HStack {
                        StatBox(value: "\(stats.totalGames)", label: "Games", color: .primary)
                        StatBox(value: "\(stats.wins)", label: "Wins", color: .green)
                        StatBox(value: "\(stats.losses)", label: "Losses", color: .red)
                        StatBox(value: stats.winRateText, label: "Win %", color: .blue)
                    }
                    .padding(.vertical, 4)

                    // Role breakdown
                    if !stats.roleBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Roles Played")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(stats.roleBreakdown.sorted(by: { $0.value > $1.value }), id: \.key) { role, count in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(role.color)
                                        .frame(width: 8, height: 8)
                                    Text(role.displayName)
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(count)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    NavigationLink {
                        GameHistoryView()
                    } label: {
                        Text("View Game History")
                    }
                } else {
                    HStack {
                        Spacer()
                        ProgressView("Loading stats...")
                        Spacer()
                    }
                }
            }

            // Friends
            if let user = user {
                Section {
                    NavigationLink {
                        FriendsListView()
                    } label: {
                        HStack {
                            Text("Friends")
                            Spacer()
                            Text("\(user.friendIds.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Error
            if let error = errorMessage {
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }

            // Sign out
            Section {
                Button("Sign Out", role: .destructive) {
                    authViewModel.signOut()
                }
                .accessibilityLabel("Sign out of your account")
            }
        }
        .navigationTitle("Profile")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditingName {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task { await saveName() }
                    }
                    .disabled(editedName.isEmpty || isSaving)
                } else {
                    Button("Edit") {
                        editedName = user?.displayName ?? ""
                        isEditingName = true
                    }
                    .disabled(user == nil)
                }
            }
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let userId = authViewModel.currentUserId else { return }
        errorMessage = nil

        do {
            async let userTask = firestoreManager.getUser(id: userId)
            async let gamesTask = firestoreManager.getFinishedGames(forUserId: userId)

            user = try await userTask
            let games = try await gamesTask

            // Calculate stats
            await calculateStats(games: games, userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func calculateStats(games: [Game], userId: String) async {
        var wins = 0
        var losses = 0
        var roleBreakdown: [Role: Int] = [:]

        for game in games {
            // Fetch players to find this user's role
            if let players = try? await firestoreManager.getPlayers(gameId: game.id),
               let myPlayer = players.first(where: { $0.userId == userId }),
               let myRole = myPlayer.role {

                roleBreakdown[myRole, default: 0] += 1

                // Determine if this was a win
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

    private func saveName() async {
        guard var updatedUser = user else { return }
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
}

// MARK: - Game Stats

private struct GameStats {
    let totalGames: Int
    let wins: Int
    let losses: Int
    let roleBreakdown: [Role: Int]

    var winRateText: String {
        guard totalGames > 0 else { return "—" }
        let rate = Double(wins) / Double(totalGames) * 100
        return "\(Int(rate))%"
    }
}

// MARK: - Stat Box

private struct StatBox: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ProfileView()
    }
    .environmentObject(AuthViewModel())
}
#endif
