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

/// A friend action, with the request or player it acts on.
enum FriendAction: Hashable {
    case sendRequest(toUserId: String)
    case acceptRequest(id: String)
    case declineRequest(id: String)
    case removeFriend(id: String)

    /// The row an action belongs to on screen.
    enum Target: Hashable {
        /// A friend request, by id: accepting or declining it.
        case request(id: String)
        /// A player found by search, by user id: sending them a request.
        case searchResult(userId: String)
        /// A friend, by user id: removing them.
        case friend(userId: String)
    }

    var target: Target {
        switch self {
        case .sendRequest(let userId): .searchResult(userId: userId)
        case .acceptRequest(let id), .declineRequest(let id): .request(id: id)
        case .removeFriend(let id): .friend(userId: id)
        }
    }

    /// The action's name for the log, without the ids it carries.
    var logName: String {
        switch self {
        case .sendRequest: "sendRequest"
        case .acceptRequest: "acceptRequest"
        case .declineRequest: "declineRequest"
        case .removeFriend: "removeFriend"
        }
    }
}

/// A friend action that didn't go through, for the alert and the line under
/// its row that say so.
struct FriendActionFailure: Equatable {
    let action: FriendAction
    let error: UserFacingError

    /// What the line under the row says, and VoiceOver hears: what didn't
    /// happen, then why.
    var message: String {
        switch action {
        case .sendRequest:
            String(
                localized: "Your friend request wasn't sent. \(error.message)",
                comment: "Shown under a search result when sending a friend request failed. The argument says why."
            )
        case .acceptRequest:
            String(
                localized: "Couldn't accept this request. \(error.message)",
                comment: "Shown under a friend request when accepting it failed. The argument says why."
            )
        case .declineRequest:
            String(
                localized: "Couldn't decline this request. \(error.message)",
                comment: "Shown under a friend request when declining it failed. The argument says why."
            )
        case .removeFriend:
            String(
                localized: "Couldn't remove this friend. \(error.message)",
                comment: "Shown under a friend when removing them failed. The argument says why."
            )
        }
    }
}

@MainActor
final class FriendsListViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var overview: Loadable<FriendsOverview, UserFacingError> = .idle
    @Published private(set) var search: Loadable<PlayerSearch, UserFacingError> = .idle
    @Published var searchText = ""
    @Published private(set) var sentRequestUserIds: Set<String> = []
    /// The friend actions running. A row with one running can't start
    /// another, so a second tap can't send a second call that fails and
    /// reports a failure for an action that went through.
    @Published private(set) var actionsInFlight: Set<FriendAction> = []
    /// The last friend action that failed, until its alert is dismissed or
    /// another action starts. Starting one clears it, so that action's own
    /// failure always shows, even if an earlier alert never presented.
    @Published private(set) var actionFailure: FriendActionFailure?

    /// Why the friends and requests didn't load, if they didn't, as their
    /// failure card says it. While the profile setup is on hold after a
    /// deletion whose outcome is unknown, a profile that isn't set up says
    /// so rather than blame the connection
    /// (`UserFacingError.whileProfileSetup(is:)`).
    var overviewFailureShown: UserFacingError? {
        overview.failure?.whileProfileSetup(is: profileSetupState())
    }

    // MARK: - Properties

    private var userId: String?
    /// Counts loads, and the changes friend actions make to what's shown, so
    /// a load can tell whether what it read is still the newest (`finishLoad`).
    private var overviewRevision = 0
    /// The revision the newest load started at.
    private var newestLoadRevision = 0
    /// Where Try Again or pull to refresh is (`retry(userId:)`). The loads
    /// read it, so the list shows it's loading for as long as a retry waits
    /// for the profile setup, even if the screen reappears meanwhile.
    private var retryPhase = RetryPhase.idle
    private let retryProfileSetup: () async -> Void
    private let profileSetupState: () -> ProfileSetupState
    private let firestoreManager: FirestoreManaging
    private let cloudFunctions: CloudFunctionsProtocol
    private let trackEvent: (String) -> Void
    private let announce: @MainActor (String) -> Void

    private static let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "Friends")

    // MARK: - Init

    /// - Parameters:
    ///   - retryProfileSetup: Gives a postponed profile setup another go and
    ///     returns once it's over: the friends list is part of the profile.
    ///     While the setup is on hold after a deletion
    ///     (`ProfileSetupState.onHoldUntilRelaunch`), it only checks whether
    ///     the account is gone. In the app this is
    ///     `AuthViewModel.retryProfileSetup()`.
    ///   - profileSetupState: How far the profile setup has got, read
    ///     whenever the screen shows a failure (`overviewFailureShown`). In
    ///     the app this is `AuthViewModel.profileSetupState`;
    ///     FriendsListView observes that view model too, so it shows a
    ///     change at once.
    ///   - trackEvent: Records an analytics event by name.
    ///   - announce: Says a message to VoiceOver.
    init(
        retryProfileSetup: @escaping () async -> Void,
        profileSetupState: @escaping () -> ProfileSetupState,
        firestoreManager: FirestoreManaging = FirestoreManager(),
        cloudFunctions: CloudFunctionsProtocol = CloudFunctions(),
        trackEvent: @escaping (String) -> Void = { AnalyticsService.trackEvent($0) },
        announce: @escaping @MainActor (String) -> Void = { FailureMessage.announce($0) }
    ) {
        self.retryProfileSetup = retryProfileSetup
        self.profileSetupState = profileSetupState
        self.firestoreManager = firestoreManager
        self.cloudFunctions = cloudFunctions
        self.trackEvent = trackEvent
        self.announce = announce
    }

    // MARK: - Data Loading

    /// Loads friends and pending requests together. What's already shown
    /// stays while this runs and if it fails. While a retry waits for the
    /// profile setup, no load starts or shows what it read: the list shows
    /// it's loading until the retry's own load (`retry(userId:)`).
    func loadData(userId: String) async {
        // It would read before the setup is over.
        guard retryPhase == .idle else { return }
        self.userId = userId
        overviewRevision += 1
        let revision = overviewRevision
        newestLoadRevision = revision
        overview.startLoading()

        let result: Result<FriendsOverview, UserFacingError>
        do {
            async let friendsTask = firestoreManager.getFriends(forUserId: userId)
            async let requestsTask = firestoreManager.getPendingFriendRequests(forUserId: userId)

            let friends = try await friendsTask
            let pendingRequests = try await requestsTask
            result = .success(FriendsOverview(friends: friends, pendingRequests: pendingRequests))
        } catch {
            Self.logger.error("Loading friends failed: \(String(describing: error), privacy: .private)")
            result = .failure(UserFacingError(error))
        }
        finishLoad(startedAt: revision, with: result)
    }

    /// Shows what the load that started at `revision` found, unless something
    /// newer is shown or on its way:
    /// - A newer load is running: that one shows its result instead.
    /// - A retry is waiting for the profile setup: this load, still reading
    ///   when the user pulled to refresh, say, read before the setup, and
    ///   the retry's own load comes once that's over.
    /// - A friend action changed the list after this load read it: the
    ///   change is newer, so the list stays as the action left it, and only
    ///   the load's ending shows. Otherwise an accepted request could come
    ///   back, with an Accept that the server would refuse.
    private func finishLoad(startedAt revision: Int, with result: Result<FriendsOverview, UserFacingError>) {
        guard revision == newestLoadRevision, retryPhase == .idle else { return }
        switch result {
        case .success(let loaded):
            overview = .loaded(revision == overviewRevision ? loaded : overview.value ?? loaded)
        case .failure(let failure):
            overview.fail(with: failure)
        }
    }

    /// Applies a friend action's change to the friends or requests shown, and
    /// makes any load already running older than it.
    private func changeOverview(_ change: (inout FriendsOverview) -> Void) {
        overview.updateValue(change)
        overviewRevision += 1
    }

    /// Try Again or pull to refresh. A profile that couldn't be set up at
    /// sign-in (offline, say) is set up first; it holds the friends list.
    /// That can take a while, so the list shows it's loading from the
    /// start, even if the screen reappears meanwhile, and another tap or
    /// pull while it waits is ignored. A retry whose task is cancelled, as
    /// when the user leaves during a pull to refresh, stops waiting and
    /// loads nothing. While the setup is on hold after a deletion
    /// (`ProfileSetupState.onHoldUntilRelaunch`), a retry only checks
    /// whether the account is gone before it loads; see
    /// `AuthViewModel.retryProfileSetup()`.
    func retry(userId: String) async {
        guard retryPhase == .idle else { return }
        retryPhase = .waitingForProfileSetup
        overview.startLoading()
        await retryProfileSetup()
        retryPhase = .idle
        guard !Task.isCancelled else { return }
        await loadData(userId: userId)
    }

    /// Where a retry is. The loads read it: a flag that only the retry
    /// checked let a load started while it waited, as when the screen
    /// reappeared, bring back the failure, with a Try Again a tap then
    /// couldn't run.
    private enum RetryPhase {
        /// Not waiting. Loads run and show what they read as usual, the
        /// retry's own too: a newer one, as when the name prompt closes,
        /// still overtakes it.
        case idle
        /// Waiting for the profile setup's attempt, with the list showing
        /// it's loading. The retry loads once the attempt is over.
        case waitingForProfileSetup
    }

    /// Loads again once the profile setup is finished, which can happen
    /// while this screen is open: when the name prompt over it closes, or
    /// when a retry sets the profile up in the background. What's shown was
    /// read before then, maybe before the profile, which holds the friends
    /// list, existed.
    func profileSetupDidChange(to state: ProfileSetupState, userId: String) async {
        guard state == .finished else { return }
        await loadData(userId: userId)
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
        let action = FriendAction.sendRequest(toUserId: user.id)
        guard start(action) else { return }

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
        } catch {
            finish(action, failingWith: error)
            return
        }
        finish(action)
        trackEvent("send_friend_request")
        sentRequestUserIds.insert(user.id)
    }

    /// Accepts the request, then reloads so the new friend appears. The
    /// request leaves the list at once, so a reload that fails can't leave
    /// it there to be accepted again.
    func acceptRequest(_ request: FriendRequest) async {
        guard let userId else { return }
        let action = FriendAction.acceptRequest(id: request.id)
        guard start(action) else { return }

        do {
            try await cloudFunctions.acceptFriendRequest(requestId: request.id)
        } catch {
            finish(action, failingWith: error)
            return
        }
        finish(action)
        trackEvent("accept_friend_request")
        changeOverview { $0.pendingRequests.removeAll { $0.id == request.id } }
        await loadData(userId: userId)
    }

    func declineRequest(_ request: FriendRequest) async {
        let action = FriendAction.declineRequest(id: request.id)
        guard start(action) else { return }

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
        } catch {
            finish(action, failingWith: error)
            return
        }
        finish(action)
        changeOverview { $0.pendingRequests.removeAll { $0.id == request.id } }
    }

    func removeFriend(_ friend: TreacheryUser) async {
        let action = FriendAction.removeFriend(id: friend.id)
        guard start(action) else { return }

        do {
            try await cloudFunctions.removeFriend(friendId: friend.id)
        } catch {
            finish(action, failingWith: error)
            return
        }
        finish(action)
        trackEvent("remove_friend")
        changeOverview { $0.friends.removeAll { $0.id == friend.id } }
    }

    /// The action running on `target`'s row, if any.
    func actionInFlight(on target: FriendAction.Target) -> FriendAction? {
        actionsInFlight.first { $0.target == target }
    }

    /// Why the last action on `target`'s row didn't go through, if it
    /// didn't. It shows under the row as well as in the alert: an alert
    /// raised while the Remove confirmation is still closing may never
    /// appear.
    func actionFailureMessage(on target: FriendAction.Target) -> String? {
        guard let actionFailure, actionFailure.action.target == target else { return nil }
        return actionFailure.message
    }

    /// Closes the alert, and the line under the row, for the last failed
    /// action.
    func dismissActionFailure() {
        actionFailure = nil
    }

    /// Starts `action`, unless its row has one running already, as after a
    /// second tap, and clears the last failure so this action's own shows.
    /// Returns whether it started.
    private func start(_ action: FriendAction) -> Bool {
        guard actionInFlight(on: action.target) == nil else { return false }
        actionsInFlight.insert(action)
        actionFailure = nil
        return true
    }

    /// Ends `action`, and if it failed, says why under its row and to
    /// VoiceOver: the failure appears away from the button that was tapped.
    private func finish(_ action: FriendAction, failingWith error: (any Error)? = nil) {
        actionsInFlight.remove(action)
        guard let error else { return }
        Self.logger.error("Friend action \(action.logName, privacy: .public) failed: \(String(describing: error), privacy: .private)")
        let failure = FriendActionFailure(action: action, error: UserFacingError(error))
        actionFailure = failure
        announce(failure.message)
    }

    // MARK: - Helpers

    func isFriend(_ user: TreacheryUser) -> Bool {
        overview.value?.friends.contains { $0.id == user.id } ?? false
    }
}
