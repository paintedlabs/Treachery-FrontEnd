//
//  FriendsListViewModel.swift
//  Treachery-iOS
//

import Foundation

@MainActor
final class FriendsListViewModel: ObservableObject {

    // MARK: - Published State

    @Published var friends: [TreacheryUser] = []
    @Published var pendingRequests: [FriendRequest] = []
    @Published var searchResults: [TreacheryUser] = []
    @Published var searchText = ""
    @Published var isSearching = false
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var sentRequestUserIds: Set<String> = []

    // MARK: - Properties

    private var userId: String?
    private let firestoreManager: FirestoreManaging
    private let cloudFunctions: CloudFunctionsProtocol

    // MARK: - Init

    init(
        firestoreManager: FirestoreManaging = FirestoreManager(),
        cloudFunctions: CloudFunctionsProtocol = CloudFunctions()
    ) {
        self.firestoreManager = firestoreManager
        self.cloudFunctions = cloudFunctions
    }

    // MARK: - Data Loading

    func loadData(userId: String) async {
        self.userId = userId
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

    // MARK: - Search

    func searchUsers() async {
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

    func sendRequest(to user: TreacheryUser) async {
        guard let userId else { return }
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
            AnalyticsService.trackEvent("send_friend_request")
            sentRequestUserIds.insert(user.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func acceptRequest(_ request: FriendRequest) async {
        guard let userId else { return }
        errorMessage = nil

        do {
            try await cloudFunctions.acceptFriendRequest(requestId: request.id)
            AnalyticsService.trackEvent("accept_friend_request")

            await loadData(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func declineRequest(_ request: FriendRequest) async {
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

    func removeFriend(_ friend: TreacheryUser) async {
        errorMessage = nil

        do {
            try await cloudFunctions.removeFriend(friendId: friend.id)
            AnalyticsService.trackEvent("remove_friend")
            friends.removeAll { $0.id == friend.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    func isFriend(_ user: TreacheryUser) -> Bool {
        friends.contains { $0.id == user.id }
    }
}
