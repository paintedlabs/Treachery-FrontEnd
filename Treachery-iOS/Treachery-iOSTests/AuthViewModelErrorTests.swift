import Testing
import Foundation
@testable import Treachery_iOS

/// The sign-in screens show `AuthViewModel.errorMessage`: a plain sentence
/// from `UserFacingError`, never Firebase's own text.
@MainActor
@Suite("Sign-in error messages")
struct AuthViewModelErrorTests {

    private let auth = MockAuthManaging()
    private let viewModel: AuthViewModel

    init() {
        viewModel = AuthViewModel(firebaseManager: auth, firestoreManager: MockFirestoreManager())
    }

    private func authError(_ code: Int) -> NSError {
        NSError(
            domain: "FIRAuthErrorDomain",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: "The password is invalid or the user does not have a password."]
        )
    }

    @Test func wrongPasswordIsSaidPlainly() async {
        auth.signInError = authError(17_009)

        await viewModel.signIn(email: "ada@example.com", password: "nope")

        #expect(viewModel.errorMessage == UserFacingError.incorrectEmailOrPassword.message)
    }

    @Test func takenEmailOnSignUpSuggestsSigningIn() async {
        auth.signInError = authError(17_007)

        await viewModel.signUp(email: "ada@example.com", password: "secret1")

        #expect(viewModel.errorMessage == UserFacingError.emailAlreadyInUse.message)
    }

    @Test func passwordResetWithoutAConnectionSaysSo() async {
        auth.signInError = authError(17_020)

        await viewModel.resetPassword(email: "ada@example.com")

        #expect(viewModel.errorMessage == UserFacingError.serverUnreachable.message)
    }

    @Test func badPhoneNumberSendsNoCodeAndSaysWhy() async {
        auth.signInError = authError(17_042)

        let verificationID = await viewModel.verifyPhoneNumber("+1555")

        #expect(verificationID == nil)
        #expect(viewModel.errorMessage == UserFacingError.invalidPhoneNumber.message)
    }

    @Test func wrongCodeIsSaidPlainly() async {
        auth.signInError = authError(17_044)

        await viewModel.signInWithPhoneCode(verificationID: "v1", code: "000000")

        #expect(viewModel.errorMessage == UserFacingError.incorrectCode.message)
    }

    @Test func unrecognizedGuestSignInFailureGetsAPlainSentence() async {
        auth.signInError = NSError(domain: "SomeSDK", code: 99, userInfo: [NSLocalizedDescriptionKey: "kErrorCode99"])

        await viewModel.signInAsGuest()

        #expect(viewModel.errorMessage == UserFacingError.unknown.message)
    }

    @Test func nobodySignedInIsNotAGuest() {
        #expect(!viewModel.isGuest)
    }
}
