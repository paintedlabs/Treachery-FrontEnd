//
//  FriendsListView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import SwiftUI

struct FriendsListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = FriendsListViewModel()

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Search section
                    VStack(spacing: 12) {
                        MtgSectionHeader(title: "Add Friends")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        OrnateDivider()
                            .padding(.horizontal, 16)

                        HStack(spacing: 8) {
                            TextField("Search by display name", text: $viewModel.searchText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .foregroundStyle(Color.mtgTextPrimary)
                                .background(Color.mtgCardElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.mtgDivider, lineWidth: 1)
                                )
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit {
                                    Task { await viewModel.searchUsers() }
                                }

                            if viewModel.isSearching {
                                ProgressView()
                                    .tint(Color.mtgGold)
                            } else if !viewModel.searchText.isEmpty {
                                Button("Search") {
                                    Task { await viewModel.searchUsers() }
                                }
                                .foregroundStyle(Color.mtgGold)
                                .font(.subheadline)
                            }
                        }
                        .padding(.horizontal, 16)

                        ForEach(viewModel.searchResults) { user in
                            if user.id != authViewModel.currentUserId {
                                HStack {
                                    Text(user.displayName)
                                        .foregroundStyle(Color.mtgTextPrimary)
                                    Spacer()
                                    if viewModel.isFriend(user) {
                                        Text("Friends")
                                            .font(.caption)
                                            .foregroundStyle(Color.mtgSuccess)
                                    } else if viewModel.sentRequestUserIds.contains(user.id) {
                                        Text("Request Sent")
                                            .font(.caption)
                                            .foregroundStyle(Color.mtgGold)
                                    } else {
                                        Button("Add") {
                                            Task { await viewModel.sendRequest(to: user) }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(Color.mtgBackground)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 4)
                                        .background(Color.mtgGold)
                                        .clipShape(Capsule())
                                        .accessibilityLabel("Send friend request to \(user.displayName)")
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                    .mtgCardFrame()

                    // Pending requests
                    if !viewModel.pendingRequests.isEmpty {
                        VStack(spacing: 0) {
                            MtgSectionHeader(title: "Friend Requests (\(viewModel.pendingRequests.count))")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, 8)

                            OrnateDivider()
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)

                            ForEach(viewModel.pendingRequests) { request in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(request.fromDisplayName)
                                            .fontWeight(.medium)
                                            .foregroundStyle(Color.mtgTextPrimary)
                                        Text("Wants to be friends")
                                            .font(.caption)
                                            .foregroundStyle(Color.mtgTextSecondary)
                                    }
                                    Spacer()
                                    Button("Accept") {
                                        Task { await viewModel.acceptRequest(request) }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(Color.mtgBackground)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.mtgSuccess)
                                    .clipShape(Capsule())
                                    .accessibilityLabel("Accept friend request from \(request.fromDisplayName)")

                                    Button("Decline") {
                                        Task { await viewModel.declineRequest(request) }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(Color.mtgTextSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.mtgDivider, lineWidth: 1)
                                    )
                                    .accessibilityLabel("Decline friend request from \(request.fromDisplayName)")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }
                        .mtgCardFrame()
                    }

                    // Friends list
                    VStack(spacing: 0) {
                        MtgSectionHeader(title: "Friends (\(viewModel.friends.count))")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        OrnateDivider()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)

                        if viewModel.isLoading {
                            MtgLoadingView()
                                .padding()
                        } else if viewModel.friends.isEmpty {
                            Text("No friends yet. Search for players above.")
                                .foregroundStyle(Color.mtgTextSecondary)
                                .font(.subheadline)
                                .padding(16)
                        } else {
                            ForEach(viewModel.friends) { friend in
                                HStack {
                                    Text(friend.displayName)
                                        .foregroundStyle(Color.mtgTextPrimary)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)

                                if friend.id != viewModel.friends.last?.id {
                                    Rectangle()
                                        .fill(Color.mtgDivider)
                                        .frame(height: 1)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                    .mtgCardFrame()

                    if let error = viewModel.errorMessage {
                        MtgErrorBanner(message: error)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { AnalyticsService.trackScreen("Friends") }
        .task {
            guard let userId = authViewModel.currentUserId else { return }
            await viewModel.loadData(userId: userId)
        }
        .refreshable {
            guard let userId = authViewModel.currentUserId else { return }
            await viewModel.loadData(userId: userId)
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        FriendsListView()
    }
    .environmentObject(AuthViewModel())
}
#endif
