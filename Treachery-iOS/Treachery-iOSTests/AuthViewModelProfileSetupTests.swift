import Testing
import Foundation
@testable import Treachery_iOS

/// A profile setup that's postponed, for an account with no profile that
/// Firebase Auth can't confirm (offline, say), is retried while that account
/// stays signed in: on a schedule, at once when the app becomes active or
/// the user taps Try Again, and never two attempts at a time.
@MainActor
@Suite("Postponed profile setup")
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
            await clock.waitForSleepers()
            elapsed += delay
            #expect(clock.pendingDeadlines == [elapsed])
            clock.advance(by: delay)
        }
        await clock.waitForSleepers()

        // The first attempt and five retries, each postponed again.
        #expect(auth.reloadAccountCalls.count == 6)
        #expect(firestore.userWriteCount == 0)
        #expect(!viewModel.isNewUser)
    }

    @Test func signingOutStopsTheRetries() async {
        viewModel.authStateDidChange(to: account())
        await clock.waitForSleepers()

        viewModel.authStateDidChange(to: nil)

        #expect(clock.pendingDeadlines.isEmpty)
        // With nothing left to set up, Try Again provisions nothing.
        await viewModel.retryProfileSetup()
        #expect(auth.reloadAccountCalls == ["u1"])
    }

    @Test func anotherAccountSigningInStopsTheFirstOnesRetries() async {
        viewModel.authStateDidChange(to: account("u1"))
        await clock.waitForSleepers()
        clock.advance(by: .seconds(2))

        viewModel.authStateDidChange(to: account("u2"))
        await clock.waitForSleepers()

        // Only u2's first retry is pending, 5 seconds after it signed in.
        #expect(clock.pendingDeadlines == [.seconds(7)])
        clock.advance(by: .seconds(5))
        await clock.waitForSleepers()
        #expect(auth.reloadAccountCalls == ["u1", "u2", "u2"])
    }

    /// An attempt still running when its account signs out or another signs
    /// in finishes without acting on its outcome: no name prompt for an
    /// account that's gone, and no sign-out of the next one.
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

        #expect(!viewModel.isNewUser)
        #expect(auth.signOutCallCount == 0)
    }

    // MARK: - Becoming active

    @Test func becomingActiveRetriesAtOnce() async {
        viewModel.authStateDidChange(to: account())
        await clock.waitForSleepers()

        viewModel.retryPostponedProfileSetup()
        await clock.waitForSleepers()

        // Retried without waiting the 5 seconds; the next retry follows the
        // schedule from there.
        #expect(auth.reloadAccountCalls.count == 2)
        #expect(clock.pendingDeadlines == [.seconds(30)])
    }

    @Test func becomingActiveWhileARetryRunsStartsNoOtherRun() async {
        viewModel.authStateDidChange(to: account())
        await clock.waitForSleepers()
        auth.whileReloadingAccount = { [viewModel] in
            // The app becomes active while the 5-second retry is running.
            viewModel.retryPostponedProfileSetup()
        }

        clock.advance(by: .seconds(5))
        await clock.waitForSleepers()

        // That retry ran alone, and the next one is due 30 seconds after it,
        // as if the app hadn't become active.
        #expect(auth.reloadAccountCalls.count == 2)
        #expect(clock.pendingDeadlines == [.seconds(35)])
    }

    // MARK: - Try Again

    @Test func tryAgainSetsUpAPostponedProfileAtOnce() async throws {
        viewModel.authStateDidChange(to: account())
        await clock.waitForSleepers()
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

    /// The whole path: Try Again on Profile gives the postponed setup another
    /// go, which creates the profile, and only then reads it.
    @Test func tryAgainOnProfileSetsUpThePostponedProfileThenShowsIt() async {
        viewModel.authStateDidChange(to: account())
        await clock.waitForSleepers()
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
    }
}
