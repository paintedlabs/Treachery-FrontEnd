import Testing
import Foundation
@testable import Treachery_iOS

/// What AuthViewModel does with each provisioning outcome: sign out an
/// account that no longer exists, and ask for a name only when the profile's
/// is a placeholder.
@MainActor
@Suite("Provisioning after sign-in")
struct AuthViewModelProvisioningTests {

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private let auth = MockAuthManaging()
    private let firestore = MockFirestoreManager()
    private let viewModel: AuthViewModel

    private let account = SignedInAccount(
        uid: "u1",
        authDisplayName: nil,
        isAnonymous: false,
        email: "ada.lovelace@example.com",
        phoneNumber: nil,
        providerIDs: ["password"],
        creationDate: nil
    )

    init() {
        viewModel = AuthViewModel(firebaseManager: auth, firestoreManager: firestore, now: { Self.now })
    }

    // MARK: - Missing profile

    @Test func deletedAccountIsSignedOutAndGetsNoProfile() async {
        auth.accountStatus = .gone

        await viewModel.provisionProfile(for: account)

        #expect(auth.signOutCallCount == 1)
        #expect(firestore.userWriteCount == 0)
        #expect(!viewModel.isNewUser)
    }

    @Test func failedSignOutOfADeletedAccountIsNotShownAsAnError() async {
        // FirebaseAuth normally signed the session out already; the extra
        // sign-out failing changes nothing the user can act on.
        auth.accountStatus = .gone
        auth.signOutError = NSError(domain: "FIRAuthErrorDomain", code: 17_995)

        await viewModel.provisionProfile(for: account)

        #expect(auth.signOutCallCount == 1)
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isNewUser)
    }

    @Test func newAccountGetsAProfileAndTheNamePrompt() async throws {
        auth.accountStatus = .exists

        await viewModel.provisionProfile(for: account)

        let call = try #require(firestore.createUserCalls.first)
        #expect(call.user.displayName == "Player")
        // The injected clock reaches the provisioner.
        #expect(call.user.createdAt == Self.now)
        #expect(viewModel.isNewUser)
        #expect(auth.signOutCallCount == 0)
    }

    @Test func unconfirmedAccountStaysSignedInWithoutAProfileOrPrompt() async {
        auth.accountStatus = .unknown

        await viewModel.provisionProfile(for: account)

        #expect(auth.signOutCallCount == 0)
        #expect(firestore.userWriteCount == 0)
        #expect(!viewModel.isNewUser)
    }

    // MARK: - Existing profile

    @Test func repairedPlaceholderNameGetsTheNamePrompt() async {
        firestore.userDocumentsToReturn["u1"] = .incomplete(missingFields: [.displayName, .createdAt, .elo])

        await viewModel.provisionProfile(for: account)

        #expect(viewModel.isNewUser)
        #expect(auth.reloadAccountCalls.isEmpty)
        #expect(auth.signOutCallCount == 0)
    }

    @Test func repairThatKeepsTheNameSkipsThePrompt() async {
        firestore.userDocumentsToReturn["u1"] = .incomplete(missingFields: [.createdAt])

        await viewModel.provisionProfile(for: account)

        #expect(firestore.repairUserProfileCalls.count == 1)
        #expect(!viewModel.isNewUser)
    }

    @Test func completeProfileChangesNothing() async {
        firestore.usersToReturn["u1"] = TreacheryUser(
            id: "u1", displayName: "Ada", friendIds: [], createdAt: Self.now
        )

        await viewModel.provisionProfile(for: account)

        #expect(firestore.userWriteCount == 0)
        #expect(auth.reloadAccountCalls.isEmpty)
        #expect(auth.signOutCallCount == 0)
        #expect(!viewModel.isNewUser)
    }

    @Test func undecodableProfileIsLeftAloneWithoutSigningOut() async {
        firestore.userDocumentsToReturn["u1"] = .undecodable

        await viewModel.provisionProfile(for: account)

        #expect(firestore.userWriteCount == 0)
        #expect(auth.signOutCallCount == 0)
        #expect(!viewModel.isNewUser)
    }

    // MARK: - Onboarding name

    @Test func onboardingNameIsNotSavedWithoutASignedInUser() async {
        await #expect(throws: FirebaseManager.AuthError.notAuthenticated) {
            try await viewModel.updateDisplayName("Ada")
        }
        #expect(firestore.userWriteCount == 0)
    }
}
