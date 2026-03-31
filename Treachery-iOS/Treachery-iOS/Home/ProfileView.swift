//
//  ProfileView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = ProfileViewModel()

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()
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

            ScrollView {
                VStack(spacing: 24) {
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

                        if let user = viewModel.user {
                            ProfileRow(label: "Display Name", value: viewModel.isEditingName ? nil : user.displayName) {
                                if viewModel.isEditingName {
                                    TextField("Name", text: $viewModel.editedName)
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
                            MtgLoadingView()
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

                        if let stats = viewModel.gameStats {
                            HStack(spacing: 8) {
                                MtgStatBox(value: "\(stats.totalGames)", label: "Games", color: Color.mtgTextPrimary)
                                MtgStatBox(value: "\(stats.wins)", label: "Wins", color: Color.mtgSuccess)
                                MtgStatBox(value: "\(stats.losses)", label: "Losses", color: Color.mtgError)
                                MtgStatBox(value: stats.winRateText, label: "Win %", color: Color.mtgGuardian)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)

                            HStack(spacing: 8) {
                                MtgStatBox(value: "\(viewModel.user?.elo ?? 1500)", label: "ELO", color: Color.mtgGoldBright)
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
                            MtgLoadingView(message: "Loading stats...")
                                .padding()
                        }
                    }
                    .mtgCardFrame()

                    // Deck Performance card
                    if let deckStats = viewModel.user?.deckStats, !deckStats.isEmpty {
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
                    if viewModel.user != nil {
                        NavigationLink {
                            FriendsListView()
                        } label: {
                            HStack {
                                Text("Friends")
                                    .foregroundStyle(Color.mtgTextPrimary)
                                Spacer()
                                Text("\(viewModel.user?.friendIds.count ?? 0)")
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
                    if let error = viewModel.errorMessage {
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { AnalyticsService.trackScreen("Profile") }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isEditingName {
                    Button(viewModel.isSaving ? "Saving..." : "Save") {
                        Task { await viewModel.saveName() }
                    }
                    .foregroundStyle(Color.mtgGold)
                    .disabled(viewModel.editedName.isEmpty || viewModel.isSaving)
                } else {
                    Button("Edit") {
                        viewModel.startEditing()
                    }
                    .foregroundStyle(Color.mtgGold)
                    .disabled(viewModel.user == nil)
                }
            }
        }
        .task {
            guard let userId = authViewModel.currentUserId else { return }
            await viewModel.loadData(userId: userId)
        }
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

#if DEBUG
#Preview {
    NavigationStack {
        ProfileView()
    }
    .environmentObject(AuthViewModel())
}
#endif
