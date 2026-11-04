import Testing
import Foundation
@testable import Treachery_iOS

@MainActor
@Suite("Friends list", .timeLimit(.minutes(1)))
struct FriendsListViewModelTests {

    private let firestore = MockFirestoreManager()
    private let cloudFunctions = MockCloudFunctions()
    private let analytics = AnalyticsEventSpy()
    private let announcer = AnnouncementSpy()
    private let viewModel: FriendsListViewModel

    /// Firestore's `unavailable`, what a read reports when it can't reach the server.
    private let unavailable = NSError(domain: "FIRFirestoreErrorDomain", code: 14)

    init() {
        viewModel = FriendsListViewModel(
            retryProfileSetup: {},
            profileSetupState: { .finished },
            firestoreManager: firestore,
            cloudFunctions: cloudFunctions,
            trackEvent: analytics.record,
            announce: announcer.record
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

        let failing = FriendsListViewModel(
            retryProfileSetup: {},
            profileSetupState: { .finished },
            firestoreManager: firestore,
            cloudFunctions: cloudFunctions,
            trackEvent: { _ in }
        )
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
    /// used to show "No friends yet" with no error and no Try Again. Try
    /// Again first sets up a profile that couldn't be at sign-in.
    @Test func missingOwnProfileFailsTheLoadThenTryAgainSetsItUp() async {
        firestore.usersToReturn = [:]
        firestore.friendsToReturn = [friend("f1")]
        var setupAttempts = 0
        let viewModel = FriendsListViewModel(
            retryProfileSetup: { [firestore] in
                setupAttempts += 1
                firestore.usersToReturn["u1"] = TreacheryUser(
                    id: "u1", displayName: "Ada", friendIds: [], createdAt: Date(timeIntervalSince1970: 1_000_000)
                )
            },
            profileSetupState: { .pending },
            firestoreManager: firestore,
            cloudFunctions: cloudFunctions,
            trackEvent: { _ in }
        )

        await viewModel.loadData(userId: "u1")

        #expect(viewModel.overview.phase == .failed)
        #expect(viewModel.overview.failure == .profileNotSetUp)
        #expect(viewModel.overview.value == nil)
        #expect(setupAttempts == 0)

        await viewModel.retry(userId: "u1")

        #expect(setupAttempts == 1)
        #expect(viewModel.overview.phase == .loaded)
        #expect(viewModel.overview.value?.friends.map(\.id) == ["f1"])
    }

    /// The setup Try Again and pull to refresh wait for can take a while:
    /// about 10 seconds, or until the connection is back. The list shows
    /// it's loading from the start, and another tap or pull meanwhile
    /// neither waits on the setup again nor loads again.
    @Test func retryShowsLoadingWhileTheSetupRunsAndIgnoresAnotherPull() async {
        let ownProfile = firestore.usersToReturn["u1"]
        firestore.usersToReturn = [:]
        firestore.friendsToReturn = [friend("f1")]
        let setup = ProfileSetupRetrySpy()
        let viewModel = FriendsListViewModel(
            retryProfileSetup: { await setup.retry() },
            profileSetupState: { .pending },
            firestoreManager: firestore,
            cloudFunctions: cloudFunctions,
            trackEvent: { _ in },
            announce: { _ in }
        )
        await viewModel.loadData(userId: "u1")
        var phaseMidSetup: LoadablePhase?
        setup.whileRetrying = { [viewModel, firestore] in
            phaseMidSetup = viewModel.overview.phase
            // Another pull while the setup runs.
            await viewModel.retry(userId: "u1")
            // The setup creates the profile.
            firestore.usersToReturn["u1"] = ownProfile
        }

        await viewModel.retry(userId: "u1")

        #expect(phaseMidSetup == .loading)
        #expect(setup.retryCount == 1)
        // The first load and the retry's: none for the second pull.
        #expect(firestore.getFriendsCallCount == 2)
        #expect(viewModel.overview.phase == .loaded)
        #expect(viewModel.overview.value?.friends.map(\.id) == ["f1"])
    }

    /// Leaving Friends during a pull to refresh cancels it. It loads nothing
    /// then, and the next pull runs as usual.
    @Test func cancelledPullToRefreshLoadsNothing() async {
        firestore.usersToReturn = [:]
        let setup = ProfileSetupRetrySpy()
        let viewModel = FriendsListViewModel(
            retryProfileSetup: { await setup.retry() },
            profileSetupState: { .pending },
            firestoreManager: firestore,
            cloudFunctions: cloudFunctions,
            trackEvent: { _ in },
            announce: { _ in }
        )
        await viewModel.loadData(userId: "u1")
        var pull: Task<Void, Never>?
        setup.whileRetrying = { pull?.cancel() }

        pull = Task { await viewModel.retry(userId: "u1") }
        await pull?.value

        #expect(setup.retryCount == 1)
        #expect(firestore.getFriendsCallCount == 1)

        await viewModel.retry(userId: "u1")

        #expect(setup.retryCount == 2)
        #expect(firestore.getFriendsCallCount == 2)
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
        #expect(viewModel.search.value?.matchedSignedInUser == false)
    }

    @Test func searchLeavesOutTheSignedInUser() async {
        await viewModel.loadData(userId: "u1")
        firestore.searchResultsToReturn = [friend("u1", named: "Ada"), friend("u2", named: "Adam")]
        viewModel.searchText = "Ad"

        await viewModel.searchUsers()

        #expect(viewModel.search.value?.players.map(\.id) == ["u2"])
        #expect(viewModel.search.value?.matchedSignedInUser == true)
    }

    /// Searching for your own name finds no one else, which the screen says
    /// as "No other players named", not "No players named".
    @Test func searchForYourOwnNameFindsNoOtherPlayers() async {
        await viewModel.loadData(userId: "u1")
        firestore.searchResultsToReturn = [friend("u1", named: "Ada")]
        viewModel.searchText = "Ada"

        await viewModel.searchUsers()

        #expect(viewModel.search.phase == .loaded)
        #expect(viewModel.search.value?.players.isEmpty == true)
        #expect(viewModel.search.value?.matchedSignedInUser == true)
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

    /// Offline with no match cached, a search can't say "No players named".
    @Test func offlineSearchWithNothingCachedSaysWhyInsteadOfNoMatches() async {
        await viewModel.loadData(userId: "u1")
        firestore.searchError = FirestoreReadError.nothingCachedOffline
        viewModel.searchText = "Zed"

        await viewModel.searchUsers()

        #expect(viewModel.search.phase == .failed)
        #expect(viewModel.search.failure == .serverUnreachable)
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

        #expect(viewModel.actionFailure == FriendActionFailure(action: .removeFriend(id: "f1"), error: .unknown))
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

    /// Left in the list under a failed reload, the request could be
    /// accepted again, and the server would refuse it.
    @Test func acceptedRequestLeavesTheListEvenIfTheReloadFails() async {
        firestore.pendingRequestsToReturn = [request("r1"), request("r2")]
        await viewModel.loadData(userId: "u1")
        firestore.friendsError = unavailable

        await viewModel.acceptRequest(request("r1"))

        #expect(cloudFunctions.acceptFriendRequestCalls == ["r1"])
        #expect(viewModel.actionFailure == nil)
        #expect(viewModel.overview.phase == .failed)
        #expect(viewModel.overview.value?.pendingRequests.map(\.id) == ["r2"])
    }

    /// The server's refusal is developer text; players get a sentence.
    @Test func failedAcceptSaysWhyInPlainWordsAndDoesNotReload() async {
        firestore.pendingRequestsToReturn = [request("r1")]
        await viewModel.loadData(userId: "u1")
        cloudFunctions.errorToThrow = NSError(
            domain: "com.firebase.functions",
            code: 9,
            userInfo: [NSLocalizedDescriptionKey: "Request is not pending."]
        )

        await viewModel.acceptRequest(request("r1"))

        #expect(viewModel.actionFailure == FriendActionFailure(
            action: .acceptRequest(id: "r1"),
            error: .requestAlreadyAnswered
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

        #expect(viewModel.actionFailure == FriendActionFailure(action: .declineRequest(id: "r1"), error: .notPermitted))
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

        #expect(viewModel.actionFailure == FriendActionFailure(action: .sendRequest(toUserId: "u3"), error: .serverUnreachable))
        #expect(viewModel.sentRequestUserIds == ["u2"])
        #expect(analytics.events == ["send_friend_request"])
    }

    /// A failure whose alert never presented can't hide the next action's:
    /// each action starts with no failure set.
    @Test func startingAnActionClearsAFailureLeftFromAnEarlierOne() async {
        firestore.friendsToReturn = [friend("f1"), friend("f2")]
        firestore.pendingRequestsToReturn = [request("r1")]
        await viewModel.loadData(userId: "u1")
        firestore.friendRequestWriteError = NSError(domain: "FIRFirestoreErrorDomain", code: 14)
        await viewModel.declineRequest(request("r1"))
        #expect(viewModel.actionFailure?.action == .declineRequest(id: "r1"))

        await viewModel.removeFriend(friend("f1"))

        #expect(viewModel.actionFailure == nil)
        #expect(viewModel.overview.value?.friends.map(\.id) == ["f2"])
    }

    // MARK: - Actions in Flight

    /// A second tap while Accept runs, as during a cold start, sends nothing:
    /// a second call would fail on the server and report a failure for a
    /// request that was accepted. Decline on the same row waits too.
    @Test func secondTapWhileAcceptRunsSendsNothing() async {
        let r1 = request("r1")
        firestore.pendingRequestsToReturn = [r1, request("r2")]
        await viewModel.loadData(userId: "u1")
        var actionMidAccept: FriendAction?
        var otherRowMidAccept: FriendAction?
        cloudFunctions.whileAcceptingFriendRequest = { [viewModel] in
            actionMidAccept = viewModel.actionInFlight(on: .request(id: "r1"))
            otherRowMidAccept = viewModel.actionInFlight(on: .request(id: "r2"))
            await viewModel.acceptRequest(r1)
            await viewModel.declineRequest(r1)
        }

        await viewModel.acceptRequest(r1)

        #expect(cloudFunctions.acceptFriendRequestCalls == ["r1"])
        #expect(firestore.updateFriendRequestCalls.isEmpty)
        #expect(actionMidAccept == .acceptRequest(id: "r1"))
        #expect(otherRowMidAccept == nil)
        #expect(viewModel.actionsInFlight.isEmpty)
        #expect(viewModel.actionFailure == nil)
    }

    /// A reload that read the requests before Accept went through, and
    /// answers after it, can't bring the accepted request back with a
    /// working Accept.
    @Test func reloadOverlappingAnAcceptDoesNotBringTheRequestBack() async {
        let r1 = request("r1")
        let newFriend = friend("f1")
        firestore.pendingRequestsToReturn = [r1]
        await viewModel.loadData(userId: "u1")
        firestore.whileReturningPendingFriendRequests = { [viewModel, firestore] in
            // This reload read r1 as pending. Now it's accepted, and the
            // accept's own reload finds the new friend.
            firestore.pendingRequestsToReturn = []
            firestore.friendsToReturn = [newFriend]
            await viewModel.acceptRequest(r1)
        }

        await viewModel.loadData(userId: "u1")

        #expect(cloudFunctions.acceptFriendRequestCalls == ["r1"])
        #expect(viewModel.overview.phase == .loaded)
        #expect(viewModel.overview.value?.pendingRequests.isEmpty == true)
        #expect(viewModel.overview.value?.friends.map(\.id) == ["f1"])
    }

    /// The same for a decline, which doesn't reload: the list stays as the
    /// decline left it, and the reload still ends.
    @Test func reloadOverlappingADeclineKeepsTheRequestDeclined() async {
        let r1 = request("r1")
        firestore.pendingRequestsToReturn = [r1, request("r2")]
        await viewModel.loadData(userId: "u1")
        firestore.whileReturningPendingFriendRequests = { [viewModel] in
            await viewModel.declineRequest(r1)
        }

        await viewModel.loadData(userId: "u1")

        #expect(firestore.updateFriendRequestCalls.map(\.id) == ["r1"])
        #expect(viewModel.overview.phase == .loaded)
        #expect(viewModel.overview.value?.pendingRequests.map(\.id) == ["r2"])
    }

    /// A failed action is said under its row and to VoiceOver, not only in
    /// the alert: an alert raised while the Remove confirmation is still
    /// closing may never appear.
    @Test func failedRemoveIsSaidUnderTheFriendAndAnnounced() async {
        firestore.friendsToReturn = [friend("f1"), friend("f2")]
        await viewModel.loadData(userId: "u1")
        cloudFunctions.errorToThrow = NSError(domain: "com.firebase.functions", code: 14)

        await viewModel.removeFriend(friend("f1"))

        let message = "Couldn't remove this friend. Couldn't reach the server. Check your connection and try again."
        #expect(viewModel.actionFailureMessage(on: .friend(userId: "f1")) == message)
        #expect(viewModel.actionFailureMessage(on: .friend(userId: "f2")) == nil)
        #expect(viewModel.actionFailureMessage(on: .searchResult(userId: "f1")) == nil)
        #expect(announcer.announcements == [message])

        // Closing the alert clears the line too.
        viewModel.dismissActionFailure()
        #expect(viewModel.actionFailureMessage(on: .friend(userId: "f1")) == nil)
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

// MARK: - A retry waiting for the profile setup

// While a retry waits for the profile setup, which can take a while, no
// load, whether asked for meanwhile or already reading, brings the
// failure back.
@MainActor
extension FriendsListViewModelTests {

    /// Friends can reappear while a retry waits for the setup, as when the
    /// user switches tabs and back, and it then loads again. That load would
    /// read before the setup is over and bring the failure back, with a Try
    /// Again a tap couldn't run. So the list goes on showing it's loading,
    /// and the retry's own load, once the setup is over, shows the friends.
    @Test func reappearingWhileARetryWaitsKeepsShowingLoading() async {
        let ownProfile = firestore.usersToReturn["u1"]
        firestore.usersToReturn = [:]
        firestore.friendsToReturn = [friend("f1")]
        let setup = ProfileSetupRetrySpy()
        let viewModel = FriendsListViewModel(
            retryProfileSetup: { await setup.retry() },
            profileSetupState: { .pending },
            firestoreManager: firestore,
            cloudFunctions: cloudFunctions,
            trackEvent: { _ in },
            announce: { _ in }
        )
        await viewModel.loadData(userId: "u1")
        var phaseAfterReappearing: LoadablePhase?
        setup.whileRetrying = { [viewModel, firestore] in
            // The screen reappears and loads again.
            await viewModel.loadData(userId: "u1")
            phaseAfterReappearing = viewModel.overview.phase
            // The setup creates the profile.
            firestore.usersToReturn["u1"] = ownProfile
        }

        await viewModel.retry(userId: "u1")

        #expect(phaseAfterReappearing == .loading)
        // The first load and the retry's: none for the screen reappearing.
        #expect(firestore.getFriendsCallCount == 2)
        #expect(viewModel.overview.phase == .loaded)
        #expect(viewModel.overview.value?.friends.map(\.id) == ["f1"])
    }

    /// A pull to refresh can start while a load is still reading, as just
    /// after the screen appears. That load read before the setup, so
    /// finishing while the retry waits, it changes nothing: the list goes on
    /// showing it's loading until the retry's own load.
    @Test func aLoadReadingWhenTheUserPullsToRefreshChangesNothing() async {
        let ownProfile = firestore.usersToReturn["u1"]
        firestore.usersToReturn = [:]
        firestore.friendsToReturn = [friend("f1")]
        let setup = ProfileSetupRetrySpy()
        let viewModel = FriendsListViewModel(
            retryProfileSetup: { await setup.retry() },
            profileSetupState: { .pending },
            firestoreManager: firestore,
            cloudFunctions: cloudFunctions,
            trackEvent: { _ in },
            announce: { _ in }
        )
        let (pullWaits, pullIsWaiting) = AsyncStream<Void>.makeStream()
        let (earlierLoadEnds, endEarlierLoad) = AsyncStream<Void>.makeStream()
        var phaseMidSetup: LoadablePhase?
        setup.whileRetrying = { [viewModel, firestore] in
            pullIsWaiting.finish()
            // The earlier load ends while the pull waits.
            for await _ in earlierLoadEnds {}
            phaseMidSetup = viewModel.overview.phase
            // The setup creates the profile.
            firestore.usersToReturn["u1"] = ownProfile
        }
        var pull: Task<Void, Never>?
        firestore.whileGettingFriends = { [viewModel] in
            // While this load reads, the user pulls to refresh.
            pull = Task { await viewModel.retry(userId: "u1") }
            for await _ in pullWaits {}
        }

        await viewModel.loadData(userId: "u1")
        endEarlierLoad.finish()
        await pull?.value

        #expect(phaseMidSetup == .loading)
        #expect(viewModel.overview.phase == .loaded)
        #expect(viewModel.overview.value?.friends.map(\.id) == ["f1"])
    }
}
