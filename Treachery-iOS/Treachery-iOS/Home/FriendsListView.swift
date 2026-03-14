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
        List {
            // Search section
            Section("Add Friends") {
                HStack {
                    TextField("Search by display name", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .onSubmit {
                            Task { await searchUsers() }
                        }
                    if isSearching {
                        ProgressView()
                    } else if !searchText.isEmpty {
                        Button("Search") {
                            Task { await searchUsers() }
                        }
                    }
                }

                ForEach(searchResults) { user in
                    if user.id != authViewModel.currentUserId {
                        HStack {
                            Text(user.displayName)
                            Spacer()
                            if isFriend(user) {
                                Text("Friends")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else if sentRequestUserIds.contains(user.id) {
                                Text("Request Sent")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else {
                                Button("Add") {
                                    Task { await sendRequest(to: user) }
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                                .accessibilityLabel("Send friend request to \(user.displayName)")
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            // Pending requests
            if !pendingRequests.isEmpty {
                Section("Friend Requests (\(pendingRequests.count))") {
                    ForEach(pendingRequests) { request in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(request.fromDisplayName)
                                    .fontWeight(.medium)
                                Text("Wants to be friends")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Accept") {
                                Task { await acceptRequest(request) }
                            }
                            .buttonStyle(.borderedProminent)
                            .font(.caption)
                            .accessibilityLabel("Accept friend request from \(request.fromDisplayName)")

                            Button("Decline") {
                                Task { await declineRequest(request) }
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                            .accessibilityLabel("Decline friend request from \(request.fromDisplayName)")
                        }
                    }
                }
            }

            // Friends list
            Section("Friends (\(friends.count))") {
                if isLoading {
                    ProgressView()
                } else if friends.isEmpty {
                    Text("No friends yet. Search for players above.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(friends) { friend in
                        Text(friend.displayName)
                    }
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Friends")
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
            var updatedRequest = request
            updatedRequest = FriendRequest(
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
