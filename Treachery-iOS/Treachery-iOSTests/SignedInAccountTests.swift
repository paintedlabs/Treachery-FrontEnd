import Testing
import Foundation
@testable import Treachery_iOS

@Suite("Signed-in account")
struct SignedInAccountTests {

    private func account(
        authDisplayName: String? = nil,
        isAnonymous: Bool = false,
        email: String? = nil,
        phoneNumber: String? = nil,
        providerIDs: [String] = []
    ) -> SignedInAccount {
        SignedInAccount(
            uid: "u1",
            authDisplayName: authDisplayName,
            isAnonymous: isAnonymous,
            email: email,
            phoneNumber: phoneNumber,
            providerIDs: providerIDs,
            creationDate: nil
        )
    }

    // MARK: - Initial display name

    @Test func guestStartsAsGuest() {
        #expect(account(isAnonymous: true).initialDisplayName == "Guest")
    }

    @Test func emailAccountStartsAsPlayerNotItsEmail() {
        let emailAccount = account(email: "ada.lovelace@example.com", providerIDs: ["password"])
        #expect(emailAccount.initialDisplayName == "Player")
    }

    @Test func phoneAccountStartsAsPlayerNotItsNumber() {
        let phoneAccount = account(phoneNumber: "+15551234567", providerIDs: ["phone"])
        #expect(phoneAccount.initialDisplayName == "Player")
    }

    @Test func authDisplayNameWinsWhenPresent() {
        #expect(account(authDisplayName: "Ada", email: "ada@example.com").initialDisplayName == "Ada")
    }

    @Test func blankAuthDisplayNameIsIgnored() {
        #expect(account(authDisplayName: "  ", email: "ada@example.com").initialDisplayName == "Player")
        #expect(account(authDisplayName: "", isAnonymous: true).initialDisplayName == "Guest")
    }

    // MARK: - auth_method

    @Test func authMethodLabelsEachWayToSignIn() {
        #expect(account(isAnonymous: true).authMethod == .guest)
        #expect(account(phoneNumber: "+15551234567", providerIDs: ["phone"]).authMethod == .phone)
        #expect(account(email: "ada@example.com", providerIDs: ["password"]).authMethod == .email)
        #expect(AuthMethod.phone.rawValue == "phone")
    }
}

@Suite("Account status after a failed reload")
struct AccountStatusTests {

    /// FIRAuthErrorCode values: userNotFound, userDisabled, invalidUserToken,
    /// userTokenExpired. FirebaseAuth signs the session out on each of them.
    @Test(arguments: [17_011, 17_005, 17_017, 17_021])
    func errorsThatEndTheSessionMeanTheAccountIsGone(code: Int) {
        let error = NSError(domain: "FIRAuthErrorDomain", code: code)
        #expect(AccountStatus(reloadError: error) == .gone)
    }

    /// networkError, tooManyRequests, internalError.
    @Test(arguments: [17_020, 17_010, 17_999])
    func otherAuthErrorsSayNothingAboutTheAccount(code: Int) {
        let error = NSError(domain: "FIRAuthErrorDomain", code: code)
        #expect(AccountStatus(reloadError: error) == .unknown)
    }

    /// keychainError: reload throws it only after the server answered for
    /// the account, when saving the refreshed user locally fails.
    @Test func keychainErrorMeansTheServerConfirmedTheAccount() {
        let error = NSError(domain: "FIRAuthErrorDomain", code: 17_995)
        #expect(AccountStatus(reloadError: error) == .exists)
    }

    @Test func errorsFromOtherDomainsSayNothingAboutTheAccount() {
        #expect(AccountStatus(reloadError: URLError(.notConnectedToInternet)) == .unknown)
        // userNotFound's code, but not from Firebase Auth.
        #expect(AccountStatus(reloadError: NSError(domain: "SomeOtherDomain", code: 17_011)) == .unknown)
    }
}
