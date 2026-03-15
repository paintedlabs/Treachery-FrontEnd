//
//  FriendsListView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import SwiftUI

struct FriendsListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var friends: [TreacheryUser] = []
    @State private var pendingRequests: [FriendRequest] = []
    @State private var searchText = ""
    @State private var searchResults: [TreacheryUser] = []
    @State private var isSearching = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var sentRequestUserIds: Set<String> = []

    private let firestoreManager = FirestoreManager()

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
                            TextField("Search by display name", text: $searchText)
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
                                    Task { await searchUsers() }
                                }

                            if isSearching {
                                ProgressView()
                                    .tint(Color.mtgGold)
                            } else if !searchText.isEmpty {
                                Button("Search") {
                                    Task { await searchUsers() }
                                }
                                .foregroundStyle(Color.mtgGold)
                                .font(.subheadline)
                            }
                        }
                        .padding(.horizontal, 16)

                        ForEach(searchResults) { user in
                            if user.id != authViewModel.currentUserId {
                                HStack {
                                    Text(user.displayName)
                                        .foregroundStyle(Color.mtgTextPrimary)
                                    Spacer()
                                    if isFriend(user) {
                                        Text("Friends")
                                            .font(.caption)
                                            .foregroundStyle(Color.mtgSuccess)
                                    } else if sentRequestUserIds.contains(user.id) {
                                        Text("Request Sent")
                                            .font(.caption)
                                            .foregroundStyle(Color.mtgGold)
                                    } else {
                                        Button("Add") {
                                            Task { await sendRequest(to: user) }
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
                    if !pendingRequests.isEmpty {
                        VStack(spacing: 0) {
                            MtgSectionHeader(title: "Friend Requests (\(pendingRequests.count))")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, 8)

                            OrnateDivider()
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)

                            ForEach(pendingRequests) { request in
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
                                        Task { await acceptRequest(request) }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(Color.mtgBackground)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.mtgSuccess)
                                    .clipShape(Capsule())
                                    .accessibilityLabel("Accept friend request from \(request.fromDisplayName)")

                                    Button("Decline") {
                                        Task { await declineRequest(request) }
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
                        MtgSectionHeader(title: "Friends (\(friends.count))")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        OrnateDivider()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)

                        if isLoading {
                            ProgressView()
                                .tint(Color.mtgGold)
                                .padding()
                        } else if friends.isEmpty {
                            Text("No friends yet. Search for players above.")
                                .foregroundStyle(Color.mtgTextSecondary)
                                .font(.subheadline)
                                .padding(16)
                        } else {
                            ForEach(friends) { friend in
                                HStack {
                                    Text(friend.displayName)
                                        .foregroundStyle(Color.mtgTextPrimary)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)

                                if friend.id != friends.last?.id {
                                    Rectangle()
                                        .fill(Color.mtgDivider)
                                        .frame(height: 1)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                    .mtgCardFrame()

                    if let error = errorMessage {
                        MtgErrorBanner(message: error)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Friends")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let userId = authViewModel.currentUserId else { return }
        isLoading = true
        errorMessage = nil

        do {
            async let friendsTask = firestoreManager.getFriends(forUserId: userId)
            async let requestsTask = firestoreManager.getPendingFriendRequests(forUserId: userId)

            friends = try await friendsTask
            pendingRequests = try await requestsTask
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func searchUsers() async {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil

        do {
            searchResults = try await firestoreManager.searchUsers(
                byDisplayName: searchText.trimmingCharacters(in: .whitespaces)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }

    // MARK: - Friend Actions

    private func sendRequest(to user: TreacheryUser) async {
        guard let userId = authViewModel.currentUserId else { return }
        errorMessage = nil

        do {
            let currentUser = try await firestoreManager.getUser(id: userId)
            let request = FriendRequest(
                id: UUID().uuidString,
                fromUserId: userId,
                fromDisplayName: currentUser?.displayName ?? "Player",
                toUserId: user.id,
                status: .pending,
                createdAt: Date()
            )
            try await firestoreManager.sendFriendRequest(request)
            // Track sent request for UI feedback
            sentRequestUserIds.insert(user.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func acceptRequest(_ request: FriendRequest) async {
        guard let userId = authViewModel.currentUserId else { return }
        errorMessage = nil

        do {
            // Update request status
            let updatedRequest = FriendRequest(
                id: request.id,
                fromUserId: request.fromUserId,
                fromDisplayName: request.fromDisplayName,
                toUserId: request.toUserId,
                status: .accepted,
                createdAt: request.createdAt
            )
            try await firestoreManager.updateFriendRequest(updatedRequest)

            // Add to both friend lists
            try await firestoreManager.addFriend(userId: userId, friendId: request.fromUserId)

            // Refresh data
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func declineRequest(_ request: FriendRequest) async {
        errorMessage = nil

        do {
            let updatedRequest = FriendRequest(
                id: request.id,
                fromUserId: request.fromUserId,
                fromDisplayName: request.fromDisplayName,
                toUserId: request.toUserId,
                status: .declined,
                createdAt: request.createdAt
            )
            try await firestoreManager.updateFriendRequest(updatedRequest)
            pendingRequests.removeAll { $0.id == request.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func isFriend(_ user: TreacheryUser) -> Bool {
        friends.contains { $0.id == user.id }
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
