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
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Profile info card
                    VStack(spacing: 0) {
                        MtgSectionHeader(title: "Profile")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        OrnateDivider()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)

                        if let user = user {
                            ProfileRow(label: "Display Name", value: isEditingName ? nil : user.displayName) {
                                if isEditingName {
                                    TextField("Name", text: $editedName)
                                        .multilineTextAlignment(.trailing)
                                        .textInputAutocapitalization(.words)
                                        .foregroundStyle(Color.mtgGoldBright)
                                }
                            }

                            ProfileRow(label: "Member Since") {
                                Text(user.createdAt, style: .date)
                                    .foregroundStyle(Color.mtgTextSecondary)
                            }
                        } else {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(Color.mtgGold)
                                Spacer()
                            }
                            .padding()
                        }
                    }
                    .mtgCardFrame()

                    // Game stats card
                    VStack(spacing: 0) {
                        MtgSectionHeader(title: "Game Stats")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        OrnateDivider()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)

                        if let stats = gameStats {
                            HStack(spacing: 8) {
                                MtgStatBox(value: "\(stats.totalGames)", label: "Games", color: Color.mtgTextPrimary)
                                MtgStatBox(value: "\(stats.wins)", label: "Wins", color: Color.mtgSuccess)
                                MtgStatBox(value: "\(stats.losses)", label: "Losses", color: Color.mtgError)
                                MtgStatBox(value: stats.winRateText, label: "Win %", color: Color.mtgGuardian)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)

                            HStack(spacing: 8) {
                                MtgStatBox(value: "\(user?.elo ?? 1500)", label: "ELO", color: Color.mtgGoldBright)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)

                            // Role breakdown
                            if !stats.roleBreakdown.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Roles Played")
                                        .font(.caption)
                                        .foregroundStyle(Color.mtgTextSecondary)
                                    ForEach(stats.roleBreakdown.sorted(by: { $0.value > $1.value }), id: \.key) { role, count in
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(role.color)
                                                .frame(width: 8, height: 8)
                                            Text(role.displayName)
                                                .font(.subheadline)
                                                .foregroundStyle(Color.mtgTextPrimary)
                                            Spacer()
                                            Text("\(count)")
                                                .font(.subheadline)
                                                .foregroundStyle(Color.mtgTextSecondary)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                            }

                            NavigationLink {
                                GameHistoryView()
                            } label: {
                                HStack {
                                    Text("View Game History")
                                        .foregroundStyle(Color.mtgGold)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(Color.mtgTextSecondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                        } else {
                            HStack {
                                Spacer()
                                ProgressView("Loading stats...")
                                    .tint(Color.mtgGold)
                                    .foregroundStyle(Color.mtgTextSecondary)
                                Spacer()
                            }
                            .padding()
                        }
                    }
                    .mtgCardFrame()

                    // Deck Performance card
                    if let deckStats = user?.deckStats, !deckStats.isEmpty {
                        VStack(spacing: 0) {
                            MtgSectionHeader(title: "Deck Performance")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, 8)

                            OrnateDivider()
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)

                            ForEach(deckStats.sorted(by: { $0.value.games > $1.value.games }), id: \.key) { deckName, stat in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(deckName)
                                        .font(.system(.subheadline, design: .serif))
                                        .italic()
                                        .foregroundStyle(Color.mtgGoldBright)

                                    HStack(spacing: 16) {
                                        HStack(spacing: 4) {
                                            Text("ELO")
                                                .font(.caption)
                                                .foregroundStyle(Color.mtgTextSecondary)
                                            Text("\(stat.elo)")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Color.mtgGoldBright)
                                        }

                                        HStack(spacing: 4) {
                                            Text("Record")
                                                .font(.caption)
                                                .foregroundStyle(Color.mtgTextSecondary)
                                            Text("\(stat.wins)W - \(stat.losses)L")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Color.mtgTextPrimary)
                                        }

                                        HStack(spacing: 4) {
                                            Text("Games")
                                                .font(.caption)
                                                .foregroundStyle(Color.mtgTextSecondary)
                                            Text("\(stat.games)")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Color.mtgTextPrimary)
                                        }

                                        Spacer()
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }
                        .mtgCardFrame()
                    }

                    // Friends card
                    if let user = user {
                        NavigationLink {
                            FriendsListView()
                        } label: {
                            HStack {
                                Text("Friends")
                                    .foregroundStyle(Color.mtgTextPrimary)
                                Spacer()
                                Text("\(user.friendIds.count)")
                                    .foregroundStyle(Color.mtgTextSecondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Color.mtgTextSecondary)
                            }
                            .padding(16)
                        }
                        .mtgCardFrame()
                    }

                    // Error
                    if let error = errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            MtgErrorBanner(message: "Error loading profile")
                            Text(error)
                                .foregroundStyle(Color.mtgError)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        .padding(16)
                        .mtgCardFrame(borderColor: Color.mtgError)
                    }

                    // Sign out
                    Button("Sign Out") {
                        authViewModel.signOut()
                    }
                    .foregroundStyle(Color.mtgError)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .mtgCardFrame(borderColor: Color.mtgError.opacity(0.5))
                    .accessibilityLabel("Sign out of your account")
                }
                .padding()
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { AnalyticsService.trackScreen("Profile") }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditingName {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task { await saveName() }
                    }
                    .foregroundStyle(Color.mtgGold)
                    .disabled(editedName.isEmpty || isSaving)
                } else {
                    Button("Edit") {
                        editedName = user?.displayName ?? ""
                        isEditingName = true
                    }
                    .foregroundStyle(Color.mtgGold)
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

// MARK: - Profile Row

private struct ProfileRow<Content: View>: View {
    let label: String
    var value: String? = nil
    var content: (() -> Content)? = nil

    init(label: String, value: String?, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.value = value
        self.content = content
    }

    init(label: String, value: String) where Content == EmptyView {
        self.label = label
        self.value = value
        self.content = nil
    }

    init(label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.value = nil
        self.content = content
    }

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.mtgTextPrimary)
            Spacer()
            if let value = value {
                Text(value)
                    .foregroundStyle(Color.mtgTextSecondary)
            }
            if let content = content {
                content()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Game Stats

private struct GameStats {
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

#if DEBUG
#Preview {
    NavigationStack {
        ProfileView()
    }
    .environmentObject(AuthViewModel())
}
#endif
