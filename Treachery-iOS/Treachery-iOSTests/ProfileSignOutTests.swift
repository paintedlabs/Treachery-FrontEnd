import Testing
import Foundation
@testable import Treachery_iOS

/// Sign Out from the Profile screen: email and phone accounts sign out at
/// once; a guest, whose account can't be signed back into, confirms first.
@MainActor
@Suite("Profile sign-out")
struct ProfileSignOutTests {

    private let session = SessionEndingSpy()
    private let cloudFunctions = MockCloudFunctions()
    private let viewModel: ProfileViewModel

    init() {
        viewModel = ProfileViewModel(
            session: session,
            firestoreManager: MockFirestoreManager(),
            cloudFunctions: cloudFunctions,
            trackEvent: { _ in }
        )
    }

    // MARK: - Email and phone accounts

    @Test func accountThatCanSignBackInSignsOutAtOnce() {
        viewModel.requestSignOut()

        #expect(session.endSessionCallCount == 1)
        #expect(viewModel.signOutState == .idle)
    }

    // MARK: - Guests

    @Test func guestIsAskedToConfirmFirst() {
        session.isGuest = true

        viewModel.requestSignOut()

        #expect(viewModel.signOutState == .confirmingGuestSignOut)
        #expect(session.endSessionCallCount == 0)
    }

    @Test func guestWhoConfirmsIsSignedOut() {
        session.isGuest = true
        viewModel.requestSignOut()

        viewModel.confirmGuestSignOut()

        #expect(session.endSessionCallCount == 1)
        #expect(viewModel.signOutState == .idle)
    }

    @Test func guestWhoCancelsStaysSignedIn() {
        session.isGuest = true
        viewModel.requestSignOut()

        viewModel.cancelSignOut()

        #expect(viewModel.signOutState == .idle)
        #expect(session.endSessionCallCount == 0)
    }

    /// SwiftUI may close the confirmation, which cancels, before it runs the
    /// Sign Out button's action; the guest still gets signed out.
    @Test func confirmationClosedBeforeItsActionStillSignsOut() {
        session.isGuest = true
        viewModel.requestSignOut()

        viewModel.cancelSignOut()
        viewModel.confirmGuestSignOut()

        #expect(session.endSessionCallCount == 1)
        #expect(viewModel.signOutState == .idle)
    }

    // MARK: - Failure

    @Test func failedSignOutSaysSoAndCanBeRetried() {
        session.errorToThrow = NSError(domain: "FIRAuthErrorDomain", code: 17_995)

        viewModel.requestSignOut()

        #expect(viewModel.signOutState == .failed(.unknown))
        #expect(viewModel.signOutFailureMessage == "Couldn't sign out. Something went wrong. Try again.")

        // Cancelling only closes a guest's confirmation; it doesn't hide a failure.
        viewModel.cancelSignOut()
        #expect(viewModel.signOutState == .failed(.unknown))

        session.errorToThrow = nil
        viewModel.requestSignOut()

        #expect(session.endSessionCallCount == 2)
        #expect(viewModel.signOutState == .idle)
        #expect(viewModel.signOutFailureMessage == nil)
    }

    /// A failed sign-out is announced after every attempt. A repeated
    /// failure changes nothing on screen, and for an email or phone account
    /// the message never clears between attempts, so announcing on a change
    /// would say only the first.
    @Test("Every failed sign-out is announced", arguments: [false, true])
    func everyFailedSignOutIsAnnounced(isGuest: Bool) {
        var announcements: [String] = []
        let viewModel = ProfileViewModel(
            session: session,
            firestoreManager: MockFirestoreManager(),
            cloudFunctions: cloudFunctions,
            trackEvent: { _ in },
            announce: { announcements.append($0) }
        )
        session.isGuest = isGuest
        session.errorToThrow = NSError(domain: "FIRAuthErrorDomain", code: 17_995)

        for _ in 1...2 {
            viewModel.requestSignOut()
            if isGuest {
                viewModel.confirmGuestSignOut()
            }
        }

        #expect(session.endSessionCallCount == 2)
        let failure = "Couldn't sign out. Something went wrong. Try again."
        #expect(announcements == [failure, failure])
    }

    // MARK: - Account deletion

    @Test func signOutIsIgnoredWhileTheAccountIsBeingDeleted() async {
        session.isGuest = true
        var stateMidDeletion: SignOutState?
        var signOutsMidDeletion: Int?
        cloudFunctions.whileDeletingAccount = { [viewModel, session] in
            viewModel.requestSignOut()
            viewModel.confirmGuestSignOut()
            stateMidDeletion = viewModel.signOutState
            signOutsMidDeletion = session.endSessionCallCount
        }

        await viewModel.deleteAccount()

        #expect(stateMidDeletion == .idle)
        #expect(signOutsMidDeletion == 0)
        // Only the deletion's own sign-out.
        #expect(session.endSessionCallCount == 1)
        #expect(viewModel.accountDeletionState == .deleted)
    }
}
