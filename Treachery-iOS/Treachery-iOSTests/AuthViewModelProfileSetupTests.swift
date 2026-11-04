import Testing
import Foundation
@testable import Treachery_iOS

/// A profile setup that's postponed, for an account with no profile that
/// Firebase Auth can't confirm (offline, say), is retried while that account
/// stays signed in: on a schedule, at once when the app becomes active or
/// the user taps Try Again, and never two attempts at a time. Once it's
/// finished, Profile and Friends load the profile again.
///
/// The tests wait on the setup: for it to sleep, or for an attempt to end.
/// Should a change stop either, the time limit fails the test, and the waits
/// end when it does rather than keep the run going.
@MainActor
@Suite("Postponed profile setup", .timeLimit(.minutes(1)))
struct AuthViewModelProfileSetupTests {

    private let auth = MockAuthManaging()
    private let firestore = MockFirestoreManager()
    private let clock = TestClock()
    private let viewModel: AuthViewModel

    init() {
        viewModel = AuthViewModel(firebaseManager: auth, firestoreManager: firestore, clock: clock)
        // No profile, and the account can't be confirmed: every attempt is
        // postponed until a test says otherwise.
        auth.accountStatus = .unknown
    }

    private func account(_ uid: String = "u1") -> SignedInAccount {
        SignedInAccount(
            uid: uid,
            authDisplayName: nil,
            isAnonymous: false,
            email: "\(uid)@example.com",
            phoneNumber: nil,
            providerIDs: ["password"],
            creationDate: nil
        )
    }

    // MARK: - Retries

    @Test func retriesSoonThenLessOftenWhileTheAccountStaysSignedIn() async {
        viewModel.authStateDidChange(to: account())

        // 5 seconds, 30 seconds and 2 minutes apart, then every 5 minutes.
        let delays: [Duration] = [.seconds(5), .seconds(30), .seconds(120), .seconds(300), .seconds(300)]
        var elapsed: Duration = .zero
        for delay in delays {
            await clock.waitForSleepersUnlessCancelled()
            elapsed += delay
            #expect(clock.pendingDeadlines == [elapsed])
            clock.advance(by: delay)
        }
        await clock.waitForSleepersUnlessCancelled()

        // The first attempt and five retries, each postponed again.
        #expect(auth.reloadAccountCalls.count == 6)
        #expect(firestore.userWriteCount == 0)
        #expect(viewModel.profileSetupState == .pending)
        #expect(!viewModel.isNewUser)
    }

    @Test func signingOutStopsTheRetries() async {
        viewModel.authStateDidChange(to: account())
        await clock.waitForSleepersUnlessCancelled()

        viewModel.authStateDidChange(to: nil)

        #expect(viewModel.profileSetupState == .noAccount)
        #expect(clock.pendingDeadlines.isEmpty)
        // With nothing left to set up, Try Again provisions nothing.
        await viewModel.retryProfileSetup()
        #expect(auth.reloadAccountCalls == ["u1"])
    }

    @Test func anotherAccountSigningInStopsTheFirstOnesRetries() async {
        viewModel.authStateDidChange(to: account("u1"))
        await clock.waitForSleepersUnlessCancelled()
        clock.advance(by: .seconds(2))

        viewModel.authStateDidChange(to: account("u2"))
        await clock.waitForSleepersUnlessCancelled()

        // Only u2's first retry is pending, 5 seconds after it signed in.
        #expect(clock.pendingDeadlines == [.seconds(7)])
        clock.advance(by: .seconds(5))
        await clock.waitForSleepersUnlessCancelled()
        #expect(auth.reloadAccountCalls == ["u1", "u2", "u2"])
    }

    /// An attempt still running when its account signs out, another signs
    /// in or the account's deletion starts creates no profile, and finishes
    /// without acting on its outcome: no name prompt for an account that's
    /// gone, and no sign-out of the next one.
    @Test("A cancelled attempt doesn't act on its outcome", arguments: [AccountStatus.exists, .gone])
    func cancelledAttemptDoesNotActOnItsOutcome(status: AccountStatus) async {
        auth.accountStatus = status
        let signedIn = account()
        var attempt: Task<Void, Never>?
        auth.whileReloadingAccount = { attempt?.cancel() }

        attempt = Task { [viewModel] in
            _ = await viewModel.provisionProfile(for: signedIn)
        }
        await attempt?.value

        #expect(firestore.createUserCalls.isEmpty)
        #expect(!viewModel.isNewUser)
        #expect(auth.signOutCallCount == 0)
    }

    /// The prompt asks for a name for the account that signed out. The next
    /// account to sign in is asked only if its own profile needs a name.
    @Test func signingOutClosesTheNamePrompt() async {
        auth.accountStatus = .exists
        viewModel.authStateDidChange(to: account())
        // Waits for the first attempt, which creates the profile.
        await viewModel.retryProfileSetup()
        #expect(viewModel.isNewUser)

        viewModel.authStateDidChange(to: nil)

        #expect(viewModel.profileSetupState == .noAccount)
        #expect(!viewModel.isNewUser)
    }

    // MARK: - Account deletion

    // The server deletes the profile, then the sign-in account. An attempt
    // in between could find the profile gone but the account still there,
    // and create the profile again, with the email and phone number, to
    // outlive the account. So nothing sets up the profile while the account
    // is being deleted. ProfileViewModel's deletion tells the session when
    // the deletion starts and if it fails; these tests stand in for it.

    @Test func aPendingRetryDoesNotRunWhileTheAccountIsBeingDeleted() async {
        viewModel.authStateDidChange(to: account())
        await clock.waitForSleepersUnlessCancelled()
        // Online again: a retry now would create the profile.
        auth.accountStatus = .exists

        viewModel.accountDeletionWillStart()

        #expect(viewModel.profileSetupState == .onHold)
        #expect(clock.pendingDeadlines.isEmpty)
        // The retry would have been due long ago, and Try Again sets nothing
        // up either: it returns at once, where it would have waited for an
        // attempt to end.
        clock.advance(by: .seconds(300))
        await viewModel.retryProfileSetup()
        #expect(auth.reloadAccountCalls == ["u1"])
        #expect(firestore.createUserCalls.isEmpty)

        // The deletion went through, and the auth state listener reports
        // the sign-out.
        viewModel.authStateDidChange(to: nil)

        #expect(viewModel.profileSetupState == .noAccount)
        #expect(auth.reloadAccountCalls == ["u1"])
        #expect(!viewModel.isNewUser)
    }

    @Test func becomingActiveWhileTheAccountIsBeingDeletedRetriesNothing() async {
        viewModel.authStateDidChange(to: account())
        await clock.waitForSleepersUnlessCancelled()
        auth.accountStatus = .exists
        viewModel.accountDeletionWillStart()

        viewModel.retryPostponedProfileSetup()
        // Waits for the attempt that becoming active would have started.
        await viewModel.retryProfileSetup()

        #expect(auth.reloadAccountCalls == ["u1"])
        #expect(firestore.createUserCalls.isEmpty)
        #expect(clock.pendingDeadlines.isEmpty)
        #expect(viewModel.profileSetupState == .onHold)
    }

    /// The deletion can start while an attempt is running. That attempt is
    /// stopped there, so it creates nothing (see the cancelled-attempt test
    /// above), and the name prompt can't open over the deletion.
    @Test func theDeletionStopsAnAttemptThatIsRunning() async {
        viewModel.authStateDidChange(to: account())
        await clock.waitForSleepersUnlessCancelled()
        auth.accountStatus = .exists
        var attemptStopped: Bool?
        auth.whileReloadingAccount = { [viewModel] in
            viewModel.accountDeletionWillStart()
            attemptStopped = Task.isCancelled
        }

        // Try Again runs an attempt now, and returns once the deletion
        // stopped it.
        await viewModel.retryProfileSetup()

        #expect(attemptStopped == true)
        #expect(viewModel.profileSetupState == .onHold)
        #expect(!viewModel.isNewUser)
    }

    /// The account is still there, and still has no profile, so the retry
    /// that was pending runs: at once, then on the usual schedule.
    @Test func aFailedDeletionResumesThePendingRetry() async {
        viewModel.authStateDidChange(to: account())
        await clock.waitForSleepersUnlessCancelled()
        clock.advance(by: .seconds(2))
        viewModel.accountDeletionWillStart()

        viewModel.accountDeletionDidFail()
        await clock.waitForSleepersUnlessCancelled()

        #expect(viewModel.profileSetupState == .pending)
        #expect(auth.reloadAccountCalls == ["u1", "u1"])
        // Retried 2 seconds in, so the next retry is due 5 seconds later.
        #expect(clock.pendingDeadlines == [.seconds(7)])
    }

    @Test func aDeletionFailingAfterTheSessionEndedResumesNothing() async {
        viewModel.authStateDidChange(to: account())
        await clock.waitForSleepersUnlessCancelled()
        viewModel.accountDeletionWillStart()
        viewModel.authStateDidChange(to: nil)

        viewModel.accountDeletionDidFail()

        #expect(viewModel.profileSetupState == .noAccount)
        #expect(clock.pendingDeadlines.isEmpty)
        await viewModel.retryProfileSetup()
        #expect(auth.reloadAccountCalls == ["u1"])
    }

    // MARK: - Becoming active

    @Test func becomingActiveRetriesAtOnce() async {
        viewModel.authStateDidChange(to: account())
        await clock.waitForSleepersUnlessCancelled()

        viewModel.retryPostponedProfileSetup()
        await clock.waitForSleepersUnlessCancelled()

        // Retried without waiting the 5 seconds; the next retry follows the
        // schedule from there.
        #expect(auth.reloadAccountCalls.count == 2)
        #expect(clock.pendingDeadlines == [.seconds(30)])
    }

    @Test func becomingActiveWhileARetryRunsStartsNoOtherRun() async {
        viewModel.authStateDidChange(to: account())
        await clock.waitForSleepersUnlessCancelled()
        auth.whileReloadingAccount = { [viewModel] in
            // The app becomes active while the 5-second retry is running.
            viewModel.retryPostponedProfileSetup()
        }

        clock.advance(by: .seconds(5))
        await clock.waitForSleepersUnlessCancelled()

        // That retry ran alone, and the next one is due 30 seconds after it,
        // as if the app hadn't become active.
        #expect(auth.reloadAccountCalls.count == 2)
        #expect(clock.pendingDeadlines == [.seconds(35)])
    }

    // MARK: - Try Again

    @Test func tryAgainSetsUpAPostponedProfileAtOnce() async throws {
        viewModel.authStateDidChange(to: account())
        await clock.waitForSleepersUnlessCancelled()
        // Back online.
        auth.accountStatus = .exists

        await viewModel.retryProfileSetup()

        // Created without waiting for the retry that was 5 seconds away,
        // and the new user is asked for a name.
        let created = try #require(firestore.createUserCalls.first)
        #expect(created.user.id == "u1")
        #expect(viewModel.isNewUser)
        #expect(clock.pendingDeadlines.isEmpty)

        // Set up, there's nothing more to retry.
        await viewModel.retryProfileSetup()
        #expect(firestore.createUserCalls.count == 1)
    }

    /// A Try Again whose task is cancelled, as when the user leaves Friends
    /// during a pull to refresh, stops waiting at once rather than when the
    /// attempt ends. The attempt goes on.
    @Test func aCancelledTryAgainStopsWaitingAtOnce() async {
        viewModel.authStateDidChange(to: account())
        await clock.waitForSleepersUnlessCancelled()
        var stoppedWaitingMidAttempt = false
        auth.whileReloadingAccount = { [viewModel] in
            // Mid-attempt, a Try Again is cancelled. Were it to wait for the
            // attempt to end, the attempt would never end.
            let tryAgain = Task { await viewModel.retryProfileSetup() }
            tryAgain.cancel()
            await tryAgain.value
            stoppedWaitingMidAttempt = true
        }

        viewModel.retryPostponedProfileSetup()
        await clock.waitForSleepersUnlessCancelled()

        #expect(stoppedWaitingMidAttempt)
        // The attempt went on, postponed again, so the next retry is due
        // 30 seconds on.
        #expect(auth.reloadAccountCalls.count == 2)
        #expect(clock.pendingDeadlines == [.seconds(30)])
    }

    /// The whole path: Try Again on Profile gives the postponed setup another
    /// go, which creates the profile, and only then reads it. That read finds
    /// the placeholder name, under the name prompt. Once the prompt has saved
    /// the user's own name and closed, Profile shows that name, though the
    /// screen never reappeared.
    @Test func tryAgainOnProfileSetsUpThePostponedProfileThenShowsTheChosenName() async throws {
        viewModel.authStateDidChange(to: account())
        await clock.waitForSleepersUnlessCancelled()
        let profileScreen = ProfileViewModel(
            session: SessionEndingSpy(),
            retryProfileSetup: { [viewModel, firestore] in
                await viewModel.retryProfileSetup()
                // The mock doesn't serve what's written; Firestore would.
                if let created = firestore.createUserCalls.last?.user {
                    firestore.usersToReturn[created.id] = created
                }
            },
            firestoreManager: firestore,
            cloudFunctions: MockCloudFunctions(),
            trackEvent: { _ in }
        )
        await profileScreen.loadData(userId: "u1")
        #expect(profileScreen.profile.failure == .profileNotSetUp)

        auth.accountStatus = .exists
        await profileScreen.retry(userId: "u1")

        #expect(firestore.createUserCalls.count == 1)
        #expect(profileScreen.profile.phase == .loaded)
        #expect(profileScreen.user?.displayName == "Player")
        #expect(viewModel.isNewUser)

        // The prompt saves the user's name, then closes. ProfileView passes
        // on the change of the setup.
        try await viewModel.updateDisplayName("Ada")
        firestore.usersToReturn["u1"]?.displayName = "Ada"
        viewModel.completeOnboarding()
        await profileScreen.profileSetupDidChange(to: viewModel.profileSetupState, userId: "u1")

        #expect(viewModel.profileSetupState == .finished)
        #expect(!viewModel.isNewUser)
        #expect(profileScreen.user?.displayName == "Ada")
    }

    /// A retry can finish the setup while Profile and Friends say the
    /// profile isn't set up yet, here by filling in a field the profile
    /// lacked, which needs no name prompt. Neither screen reappears or is
    /// tapped, but both load the profile once the setup is finished.
    @Test func profileAndFriendsLoadAProfileThatARetrySetsUpWithoutAPrompt() async {
        // A profile without created_at can't be shown, and the first attempt
        // to repair it couldn't read it from the server.
        firestore.userDocumentsToReturn["u1"] = .incomplete(missingFields: [.createdAt])
        firestore.userDocumentError = NSError(domain: "FIRFirestoreErrorDomain", code: 14)
        viewModel.authStateDidChange(to: account())
        await clock.waitForSleepersUnlessCancelled()
        let profileScreen = ProfileViewModel(
            session: SessionEndingSpy(),
            retryProfileSetup: {},
            firestoreManager: firestore,
            cloudFunctions: MockCloudFunctions(),
            trackEvent: { _ in }
        )
        let friendsScreen = FriendsListViewModel(
            retryProfileSetup: {},
            firestoreManager: firestore,
            cloudFunctions: MockCloudFunctions(),
            trackEvent: { _ in },
            announce: { _ in }
        )
        await profileScreen.loadData(userId: "u1")
        await friendsScreen.loadData(userId: "u1")
        #expect(profileScreen.profile.failure == .profileNotSetUp)
        #expect(friendsScreen.overview.failure == .profileNotSetUp)

        // Back online, the next retry repairs the profile. retryProfileSetup()
        // runs it now, as the app becoming active would, and waits for it.
        firestore.userDocumentError = nil
        await viewModel.retryProfileSetup()
        // The mock doesn't serve what's written; Firestore would.
        firestore.usersToReturn["u1"] = TreacheryUser(
            id: "u1", displayName: "Ada", friendIds: [], createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
        // Each screen passes on the change of the setup.
        await profileScreen.profileSetupDidChange(to: viewModel.profileSetupState, userId: "u1")
        await friendsScreen.profileSetupDidChange(to: viewModel.profileSetupState, userId: "u1")

        #expect(firestore.repairUserProfileCalls.count == 1)
        #expect(viewModel.profileSetupState == .finished)
        #expect(!viewModel.isNewUser)
        #expect(profileScreen.profile.phase == .loaded)
        #expect(profileScreen.user?.displayName == "Ada")
        #expect(friendsScreen.overview.phase == .loaded)
    }
}

private extension TestClock {
    /// Waits as `waitForSleepers()` does, but stops waiting once the test is
    /// cancelled. Swift Testing cancels a test that runs past its time limit,
    /// and where that's all the runner does, the clock's own wait, which
    /// ignores cancellation, would keep the run waiting after the test
    /// failed. (Xcode 27 also ends such a test itself.)
    func waitForSleepersUnlessCancelled() async {
        let (asleep, wake) = AsyncStream<Void>.makeStream()
        Task {
            await waitForSleepers()
            wake.finish()
        }
        // Ends once a sleeper is waiting, or as soon as the test is cancelled.
        for await _ in asleep {}
    }
}
