import Testing
import Foundation
@testable import Treachery_iOS

@MainActor
@Suite("Profile account deletion")
struct ProfileViewModelAccountDeletionTests {

    private let cloudFunctions = MockCloudFunctions()
    private let firestore = MockFirestoreManager()
    private let session = SessionEndingSpy()
    private let analytics = AnalyticsEventSpy()
    private let viewModel: ProfileViewModel

    /// The server's refusal (GAME_IN_PROGRESS_MESSAGE in functions/src/callables/account.js).
    private let inProgressMessage = "You're in a game that's still in progress. You can delete your account once that game ends."
    /// The error the test uses for a failed local sign-out (FIRAuthErrorCode keychainError).
    private let keychainError = NSError(domain: "FIRAuthErrorDomain", code: 17_995)

    init() {
        viewModel = ProfileViewModel(
            session: session,
            retryProfileSetup: {},
            firestoreManager: firestore,
            cloudFunctions: cloudFunctions,
            trackEvent: analytics.record
        )
    }

    // MARK: - Success

    @Test func confirmedDeletionCallsServerOnceThenSignsOut() async {
        var calls: [String] = []
        cloudFunctions.whileDeletingAccount = { calls.append("deleteAccount") }
        session.whileEndingSession = { calls.append("endSession") }

        viewModel.requestAccountDeletion()
        #expect(viewModel.accountDeletionState == .confirming)

        await viewModel.deleteAccount()

        // Sign-out comes only after the server call, and each happens once.
        #expect(calls == ["deleteAccount", "endSession"])
        #expect(cloudFunctions.deleteAccountCallCount == 1)
        #expect(session.endSessionCallCount == 1)
        #expect(analytics.events == ["account_deleted"])
        // Stays locked until the signed-out screen replaces this one.
        #expect(viewModel.accountDeletionState == .deleted)
        #expect(viewModel.accountDeletionState.isUnderway)
    }

    @Test func cancellingTheConfirmationDeletesNothing() {
        viewModel.requestAccountDeletion()
        viewModel.cancelAccountDeletion()

        #expect(viewModel.accountDeletionState == .idle)
        #expect(cloudFunctions.deleteAccountCallCount == 0)
        #expect(session.endSessionCallCount == 0)
        #expect(analytics.events.isEmpty)
    }

    // MARK: - Renaming

    @Test func deletionCannotBeRequestedWhileARenameIsSaving() async {
        firestore.usersToReturn["u1"] = TreacheryUser(
            id: "u1", displayName: "Old Name", friendIds: [], createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
        await viewModel.loadData(userId: "u1")
        viewModel.startEditing()
        viewModel.editedName = "New Name"
        var canRequestMidSave: Bool?
        var stateMidSave: AccountDeletionState?
        firestore.whileUpdatingDisplayName = { [viewModel] in
            viewModel.requestAccountDeletion()
            canRequestMidSave = viewModel.canRequestAccountDeletion
            stateMidSave = viewModel.accountDeletionState
        }

        await viewModel.saveName()

        #expect(canRequestMidSave == false)
        #expect(stateMidSave == .idle)
        #expect(viewModel.canRequestAccountDeletion)
    }

    @Test func confirmingDeletionLeavesNameEditing() async {
        viewModel.startEditing()
        #expect(viewModel.isEditingName)

        await viewModel.deleteAccount()

        #expect(!viewModel.isEditingName)
    }

    // MARK: - In-progress game

    @Test func inProgressGameShowsTheServerMessageAndStaysSignedIn() async {
        cloudFunctions.errorToThrow = AccountDeletionError.inProgressGame(message: inProgressMessage)

        await viewModel.deleteAccount()

        #expect(viewModel.accountDeletionState == .failed(message: inProgressMessage, isRetryable: false))
        #expect(session.endSessionCallCount == 0)
        #expect(analytics.events.isEmpty)
    }

    @Test func blankInProgressMessageFallsBackToLocalCopy() async {
        cloudFunctions.errorToThrow = AccountDeletionError.inProgressGame(message: "  ")

        await viewModel.deleteAccount()

        #expect(viewModel.accountDeletionState == .failed(
            message: ProfileViewModel.AccountDeletionMessage.inProgressGameFallback,
            isRetryable: false
        ))
        #expect(session.endSessionCallCount == 0)
    }

    // MARK: - Other failures

    @Test func timeoutAsksToTryAgainToFinish() async {
        cloudFunctions.errorToThrow = AccountDeletionError.timedOut

        await viewModel.deleteAccount()

        #expect(viewModel.accountDeletionState == .failed(
            message: ProfileViewModel.AccountDeletionMessage.timedOut,
            isRetryable: true
        ))
        #expect(session.endSessionCallCount == 0)

        cloudFunctions.errorToThrow = nil
        await viewModel.deleteAccount()

        #expect(cloudFunctions.deleteAccountCallCount == 2)
        #expect(viewModel.accountDeletionState == .deleted)
    }

    @Test("Other failures show a human message and can be retried", arguments: [
        URLError(.notConnectedToInternet),
        NSError(domain: "com.firebase.functions", code: 14, userInfo: [NSLocalizedDescriptionKey: "UNAVAILABLE"]),
        AccountDeletionError.unexpectedResponse,
    ] as [any Error])
    func otherFailuresAreRetryable(error: any Error) async {
        cloudFunctions.errorToThrow = error

        await viewModel.deleteAccount()

        #expect(viewModel.accountDeletionState == .failed(
            message: ProfileViewModel.AccountDeletionMessage.retry,
            isRetryable: true
        ))
        #expect(session.endSessionCallCount == 0)
        #expect(analytics.events.isEmpty)

        cloudFunctions.errorToThrow = nil
        await viewModel.deleteAccount()

        #expect(cloudFunctions.deleteAccountCallCount == 2)
        #expect(session.endSessionCallCount == 1)
        #expect(viewModel.accountDeletionState == .deleted)
    }

    // MARK: - Deleted, but sign-out failed

    @Test func signOutFailureAfterDeletionGetsItsOwnState() async {
        session.errorToThrow = keychainError

        await viewModel.deleteAccount()

        // Not `.failed`, which says the account was not deleted: it was.
        #expect(viewModel.accountDeletionState == .signOutFailed)
        #expect(viewModel.accountDeletionState.isUnderway)
        #expect(cloudFunctions.deleteAccountCallCount == 1)
        #expect(analytics.events == ["account_deleted"])
    }

    @Test func signOutFailureCannotBeDismissedBackToIdle() async {
        session.errorToThrow = keychainError
        await viewModel.deleteAccount()

        viewModel.cancelAccountDeletion()
        #expect(viewModel.accountDeletionState == .signOutFailed)

        viewModel.requestAccountDeletion()
        #expect(viewModel.accountDeletionState == .signOutFailed)
        #expect(!viewModel.canRequestAccountDeletion)

        await viewModel.deleteAccount()
        #expect(viewModel.accountDeletionState == .signOutFailed)
        #expect(cloudFunctions.deleteAccountCallCount == 1)
    }

    @Test func retryingSignOutNeverCallsTheServerAgain() async {
        session.errorToThrow = keychainError
        await viewModel.deleteAccount()

        viewModel.retrySignOut()

        #expect(viewModel.accountDeletionState == .signOutFailed)
        #expect(session.endSessionCallCount == 2)

        session.errorToThrow = nil
        viewModel.retrySignOut()

        #expect(viewModel.accountDeletionState == .deleted)
        #expect(session.endSessionCallCount == 3)
        #expect(cloudFunctions.deleteAccountCallCount == 1)
        #expect(analytics.events == ["account_deleted"])
    }

    @Test func retrySignOutDoesNothingUnlessSignOutFailed() async {
        viewModel.retrySignOut()

        #expect(viewModel.accountDeletionState == .idle)
        #expect(session.endSessionCallCount == 0)

        cloudFunctions.errorToThrow = URLError(.notConnectedToInternet)
        await viewModel.deleteAccount()
        viewModel.retrySignOut()

        #expect(session.endSessionCallCount == 0)
    }

    // MARK: - Repeat taps

    @Test func repeatTapsWhileDeletingAreIgnored() async {
        var stateWhileInFlight: AccountDeletionState?
        cloudFunctions.whileDeletingAccount = { [viewModel] in
            stateWhileInFlight = viewModel.accountDeletionState
            // Mid-request the user taps Delete Account, confirms, then dismisses.
            viewModel.requestAccountDeletion()
            await viewModel.deleteAccount()
            viewModel.cancelAccountDeletion()
        }

        await viewModel.deleteAccount()

        #expect(stateWhileInFlight == .deleting)
        #expect(cloudFunctions.deleteAccountCallCount == 1)
        #expect(session.endSessionCallCount == 1)
        #expect(viewModel.accountDeletionState == .deleted)
    }
}
