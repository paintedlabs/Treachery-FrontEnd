//
//  FriendsListViewModel.swift
//  Treachery-iOS
//

import Foundation
import os

/// The signed-in user's friends and the friend requests waiting for them
/// to answer.
struct FriendsOverview {
    var friends: [TreacheryUser]
    var pendingRequests: [FriendRequest]
}

/// A finished search for players by name.
struct PlayerSearch {
    /// What was searched for, trimmed.
    let query: String
    /// The players whose names start with `query`, never the signed-in user.
    let players: [TreacheryUser]
    /// Whether the signed-in user's own name matched too. They're left out
    /// of `players`, so a search that found no one else says "no other
    /// players" rather than "no players".
    let matchedSignedInUser: Bool
}

/// A friend action that didn't go through, for the alert that says so.
struct FriendActionFailure: Equatable {
    enum Action: Equatable {
        case sendRequest
        case acceptRequest
        case declineRequest
        case removeFriend
    }

    let action: Action
    let error: UserFacingError
}

@MainActor
final class FriendsListViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var overview: Loadable<FriendsOverview, UserFacingError> = .idle
    @Published private(set) var search: Loadable<PlayerSearch, UserFacingError> = .idle
    @Published var searchText = ""
    @Published private(set) var sentRequestUserIds: Set<String> = []
    /// The last friend action that failed, until its alert is dismissed or
    /// another action starts. Starting one clears it, so that action's own
    /// failure always shows, even if an earlier alert never presented.
    @Published private(set) var actionFailure: FriendActionFailure?

    // MARK: - Properties

    private var userId: String?
    private let firestoreManager: FirestoreManaging
    private let cloudFunctions: CloudFunctionsProtocol
    private let trackEvent: (String) -> Void

    private static let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "Friends")

    // MARK: - Init

    /// - Parameter trackEvent: Records an analytics event by name.
    init(
        firestoreManager: FirestoreManaging = FirestoreManager(),
        cloudFunctions: CloudFunctionsProtocol = CloudFunctions(),
        trackEvent: @escaping (String) -> Void = { AnalyticsService.trackEvent($0) }
    ) {
        self.firestoreManager = firestoreManager
        self.cloudFunctions = cloudFunctions
        self.trackEvent = trackEvent
    }

    // MARK: - Data Loading

    /// Loads friends and pending requests together. What's already shown
    /// stays while this runs and if it fails.
    func loadData(userId: String) async {
        self.userId = userId
        overview.startLoading()

        do {
            async let friendsTask = firestoreManager.getFriends(forUserId: userId)
            async let requestsTask = firestoreManager.getPendingFriendRequests(forUserId: userId)

            let friends = try await friendsTask
            let pendingRequests = try await requestsTask
            overview = .loaded(FriendsOverview(friends: friends, pendingRequests: pendingRequests))
        } catch {
            Self.logger.error("Loading friends failed: \(String(describing: error), privacy: .private)")
            overview.fail(with: UserFacingError(error))
        }
    }

    // MARK: - Search

    /// Searches for players whose names start with `searchText`. A failed
    /// search shows only why: results kept from another search would read
    /// as results for this one.
    func searchUsers() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        search.startLoading()

        do {
            let matches = try await firestoreManager.searchUsers(byDisplayName: query)
            let players = matches.filter { $0.id != userId }
            search = .loaded(PlayerSearch(query: query, players: players, matchedSignedInUser: players.count < matches.count))
        } catch {
            Self.logger.error("Searching for players failed: \(String(describing: error), privacy: .private)")
            search = .failed(UserFacingError(error), previous: nil)
        }
    }

    // MARK: - Friend Actions

    func sendRequest(to user: TreacheryUser) async {
        guard let userId else { return }
        actionFailure = nil

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
            trackEvent("send_friend_request")
            sentRequestUserIds.insert(user.id)
        } catch {
            fail(.sendRequest, with: error)
        }
    }

    /// Accepts the request, then reloads so the new friend appears. The
    /// request leaves the list at once, so a reload that fails can't leave
    /// it there to be accepted again.
    func acceptRequest(_ request: FriendRequest) async {
        guard let userId else { return }
        actionFailure = nil

        do {
            try await cloudFunctions.acceptFriendRequest(requestId: request.id)
            trackEvent("accept_friend_request")
        } catch {
            fail(.acceptRequest, with: error)
            return
        }
        overview.updateValue { $0.pendingRequests.removeAll { $0.id == request.id } }
        await loadData(userId: userId)
    }

    func declineRequest(_ request: FriendRequest) async {
        actionFailure = nil
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
            overview.updateValue { $0.pendingRequests.removeAll { $0.id == request.id } }
        } catch {
            fail(.declineRequest, with: error)
        }
    }

    func removeFriend(_ friend: TreacheryUser) async {
        actionFailure = nil
        do {
            try await cloudFunctions.removeFriend(friendId: friend.id)
            trackEvent("remove_friend")
            overview.updateValue { $0.friends.removeAll { $0.id == friend.id } }
        } catch {
            fail(.removeFriend, with: error)
        }
    }

    /// Closes the alert for the last failed action.
    func dismissActionFailure() {
        actionFailure = nil
    }

    private func fail(_ action: FriendActionFailure.Action, with error: any Error) {
        Self.logger.error("Friend action \(String(describing: action), privacy: .public) failed: \(String(describing: error), privacy: .private)")
        actionFailure = FriendActionFailure(action: action, error: UserFacingError(error))
    }

    // MARK: - Helpers

    func isFriend(_ user: TreacheryUser) -> Bool {
        overview.value?.friends.contains { $0.id == user.id } ?? false
    }
}
