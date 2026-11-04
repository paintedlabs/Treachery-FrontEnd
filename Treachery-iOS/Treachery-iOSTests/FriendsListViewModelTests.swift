import Testing
import Foundation
@testable import Treachery_iOS

@MainActor
@Suite("Friends list")
struct FriendsListViewModelTests {

    private let firestore = MockFirestoreManager()
    private let cloudFunctions = MockCloudFunctions()
    private let analytics = AnalyticsEventSpy()
    private let viewModel: FriendsListViewModel

    /// Firestore's `unavailable`, what a read reports when it can't reach the server.
    private let unavailable = NSError(domain: "FIRFirestoreErrorDomain", code: 14)

    init() {
        viewModel = FriendsListViewModel(
            firestoreManager: firestore,
            cloudFunctions: cloudFunctions,
            trackEvent: analytics.record
        )
        // The signed-in user's own profile, which holds their friends list.
        firestore.usersToReturn["u1"] = friend("u1", named: "Ada")
    }

    // MARK: - Loading

    @Test func loadShowsFriendsAndRequestsTogether() async {
        firestore.friendsToReturn = [friend("f1")]
        firestore.pendingRequestsToReturn = [request("r1")]
        #expect(viewModel.overview.phase == .idle)

        await viewModel.loadData(userId: "u1")

        #expect(viewModel.overview.phase == .loaded)
        #expect(viewModel.overview.value?.friends.map(\.id) == ["f1"])
        #expect(viewModel.overview.value?.pendingRequests.map(\.id) == ["r1"])
    }

    /// "No friends yet" belongs only to a load that succeeded with none.
    @Test func emptyStateComesOnlyFromASuccessfulLoad() async {
        await viewModel.loadData(userId: "u1")

        #expect(viewModel.overview.phase == .loaded)
        #expect(viewModel.overview.value?.friends.isEmpty == true)

        let failing = FriendsListViewModel(firestoreManager: firestore, cloudFunctions: cloudFunctions, trackEvent: { _ in })
        firestore.friendsError = unavailable
        await failing.loadData(userId: "u1")

        #expect(failing.overview.phase == .failed)
        #expect(failing.overview.value == nil)
    }

    @Test func failedLoadSaysWhyThenRetryLoads() async {
        firestore.friendsToReturn = [friend("f1")]
        firestore.friendsError = unavailable

        await viewModel.loadData(userId: "u1")

        #expect(viewModel.overview.failure == .serverUnreachable)
        #expect(viewModel.overview.value == nil)

        firestore.friendsError = nil
        await viewModel.loadData(userId: "u1")

        #expect(viewModel.overview.phase == .loaded)
        #expect(viewModel.overview.value?.friends.map(\.id) == ["f1"])
    }

    /// Without their own profile there's no friends list to read, which
    /// used to show "No friends yet" with no error and no Try Again.
    @Test func unreadableOwnProfileFailsTheLoadThenRetryLoads() async {
        firestore.usersToReturn = [:]
        firestore.friendsToReturn = [friend("f1")]

        await viewModel.loadData(userId: "u1")

        #expect(viewModel.overview.phase == .failed)
        #expect(viewModel.overview.failure == .unknown)
        #expect(viewModel.overview.value == nil)

        firestore.usersToReturn["u1"] = friend("u1", named: "Ada")
        await viewModel.loadData(userId: "u1")

        #expect(viewModel.overview.phase == .loaded)
        #expect(viewModel.overview.value?.friends.map(\.id) == ["f1"])
    }

    @Test func failedRefreshKeepsFriendsOnScreen() async {
        firestore.friendsToReturn = [friend("f1")]
        await viewModel.loadData(userId: "u1")
        firestore.friendsError = unavailable
        var friendsMidRefresh: [String]?
        firestore.whileGettingFriends = { [viewModel] in
            friendsMidRefresh = viewModel.overview.value?.friends.map(\.id)
        }

        await viewModel.loadData(userId: "u1")

        #expect(friendsMidRefresh == ["f1"])
        #expect(viewModel.overview.phase == .failed)
        #expect(viewModel.overview.failure == .serverUnreachable)
        #expect(viewModel.overview.value?.friends.map(\.id) == ["f1"])
    }

    // MARK: - Search

    @Test func searchWithNoMatchesRemembersWhatWasSearchedFor() async {
        await viewModel.loadData(userId: "u1")
        viewModel.searchText = "  Zed  "

        await viewModel.searchUsers()

        #expect(firestore.searchUsersCalls == ["Zed"])
        #expect(viewModel.search.phase == .loaded)
        #expect(viewModel.search.value?.query == "Zed")
        #expect(viewModel.search.value?.players.isEmpty == true)
    }

    @Test func searchLeavesOutTheSignedInUser() async {
        await viewModel.loadData(userId: "u1")
        firestore.searchResultsToReturn = [friend("u1", named: "Ada"), friend("u2", named: "Adam")]
        viewModel.searchText = "Ad"

        await viewModel.searchUsers()

        #expect(viewModel.search.value?.players.map(\.id) == ["u2"])
    }

    @Test func blankSearchSendsNothing() async {
        viewModel.searchText = "   "

        await viewModel.searchUsers()

        #expect(firestore.searchUsersCalls.isEmpty)
        #expect(viewModel.search.phase == .idle)
    }

    /// Results kept from another search would read as results for this one.
    @Test func failedSearchShowsOnlyWhy() async {
        await viewModel.loadData(userId: "u1")
        firestore.searchResultsToReturn = [friend("u2", named: "Adam")]
        viewModel.searchText = "Ad"
        await viewModel.searchUsers()
        firestore.searchError = unavailable
        viewModel.searchText = "Bo"

        await viewModel.searchUsers()

        #expect(viewModel.search.phase == .failed)
        #expect(viewModel.search.failure == .serverUnreachable)
        #expect(viewModel.search.value == nil)
    }

    // MARK: - Friend Actions

    @Test func removeFriendCallsCloudFunctionAndRemovesLocally() async {
        firestore.friendsToReturn = [friend("f1")]
        await viewModel.loadData(userId: "u1")

        await viewModel.removeFriend(friend("f1"))

        #expect(cloudFunctions.removeFriendCalls == ["f1"])
        #expect(viewModel.overview.value?.friends.isEmpty == true)
        #expect(viewModel.actionFailure == nil)
        #expect(analytics.events == ["remove_friend"])
    }

    @Test func failedRemoveKeepsTheFriendAndSaysWhyInPlainWords() async {
        firestore.friendsToReturn = [friend("f1")]
        await viewModel.loadData(userId: "u1")
        cloudFunctions.errorToThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "remove failed"])

        await viewModel.removeFriend(friend("f1"))

        #expect(viewModel.actionFailure == FriendActionFailure(action: .removeFriend, error: .unknown))
        #expect(viewModel.overview.value?.friends.count == 1)
        #expect(analytics.events.isEmpty)
        // An action failure is not a load failure.
        #expect(viewModel.overview.phase == .loaded)

        viewModel.dismissActionFailure()
        #expect(viewModel.actionFailure == nil)
    }

    @Test func acceptingReloadsSoTheNewFriendAppears() async {
        firestore.pendingRequestsToReturn = [request("r1")]
        await viewModel.loadData(userId: "u1")
        firestore.friendsToReturn = [friend("f1")]
        firestore.pendingRequestsToReturn = []

        await viewModel.acceptRequest(request("r1"))

        #expect(cloudFunctions.acceptFriendRequestCalls == ["r1"])
        #expect(analytics.events == ["accept_friend_request"])
        #expect(firestore.getFriendsCallCount == 2)
        #expect(viewModel.overview.value?.friends.map(\.id) == ["f1"])
        #expect(viewModel.overview.value?.pendingRequests.isEmpty == true)
    }

    /// The server's failed-precondition sentence is written for players.
    @Test func failedAcceptShowsTheServersSentenceAndDoesNotReload() async {
        firestore.pendingRequestsToReturn = [request("r1")]
        await viewModel.loadData(userId: "u1")
        cloudFunctions.errorToThrow = NSError(
            domain: "com.firebase.functions",
            code: 9,
            userInfo: [NSLocalizedDescriptionKey: "Request is not pending."]
        )

        await viewModel.acceptRequest(request("r1"))

        #expect(viewModel.actionFailure == FriendActionFailure(
            action: .acceptRequest,
            error: UserFacingError(message: "Request is not pending.")
        ))
        #expect(firestore.getFriendsCallCount == 1)
        #expect(viewModel.overview.value?.pendingRequests.map(\.id) == ["r1"])
    }

    @Test func decliningRemovesTheRequestLocally() async throws {
        firestore.pendingRequestsToReturn = [request("r1"), request("r2")]
        await viewModel.loadData(userId: "u1")

        await viewModel.declineRequest(request("r1"))

        let written = try #require(firestore.updateFriendRequestCalls.first)
        #expect(written.id == "r1")
        #expect(written.status == .declined)
        #expect(viewModel.overview.value?.pendingRequests.map(\.id) == ["r2"])
    }

    @Test func failedDeclineKeepsTheRequest() async {
        firestore.pendingRequestsToReturn = [request("r1")]
        await viewModel.loadData(userId: "u1")
        firestore.friendRequestWriteError = NSError(domain: "FIRFirestoreErrorDomain", code: 7)

        await viewModel.declineRequest(request("r1"))

        #expect(viewModel.actionFailure == FriendActionFailure(action: .declineRequest, error: .notPermitted))
        #expect(viewModel.overview.value?.pendingRequests.map(\.id) == ["r1"])
    }

    @Test func sentRequestIsRememberedAndAFailedOneSaysWhy() async {
        firestore.usersToReturn["u1"] = friend("u1", named: "Ada")
        await viewModel.loadData(userId: "u1")

        await viewModel.sendRequest(to: friend("u2", named: "Bob"))

        #expect(firestore.sendFriendRequestCalls.map(\.fromDisplayName) == ["Ada"])
        #expect(viewModel.sentRequestUserIds == ["u2"])
        #expect(analytics.events == ["send_friend_request"])

        firestore.friendRequestWriteError = NSError(domain: "FIRFirestoreErrorDomain", code: 14)
        await viewModel.sendRequest(to: friend("u3", named: "Cy"))

        #expect(viewModel.actionFailure == FriendActionFailure(action: .sendRequest, error: .serverUnreachable))
        #expect(viewModel.sentRequestUserIds == ["u2"])
        #expect(analytics.events == ["send_friend_request"])
    }

    // MARK: - Fixtures

    private func friend(_ id: String, named displayName: String = "Friend") -> TreacheryUser {
        TreacheryUser(id: id, displayName: displayName, friendIds: [], createdAt: Date(timeIntervalSince1970: 1_000_000))
    }

    private func request(_ id: String) -> FriendRequest {
        FriendRequest(
            id: id,
            fromUserId: "sender-\(id)",
            fromDisplayName: "Sender",
            toUserId: "u1",
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }
}
