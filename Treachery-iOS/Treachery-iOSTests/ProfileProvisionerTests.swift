import Testing
import Foundation
@testable import Treachery_iOS

/// Guests, email and phone sign-ups, and the name each new profile gets.
private let newAccountNameCases: [(isAnonymous: Bool, email: String?, phone: String?, expected: String)] = [
    (true, nil, nil, "Guest"),
    (false, "ada.lovelace@example.com", nil, "Player"),
    (false, nil, "+15551234567", "Player"),
]

@MainActor
@Suite("Profile provisioning")
struct ProfileProvisionerTests {

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    /// When Firebase Auth created the account, months before `now`.
    private static let signUpDate = Date(timeIntervalSince1970: 1_780_000_000)

    private let firestore = MockFirestoreManager()
    private let provisioner: ProfileProvisioner

    init() {
        provisioner = ProfileProvisioner(firestore: firestore, now: { Self.now })
    }

    private func account(
        isAnonymous: Bool = false,
        email: String? = "ada.lovelace@example.com",
        phoneNumber: String? = nil,
        creationDate: Date? = nil
    ) -> SignedInAccount {
        SignedInAccount(
            uid: "u1",
            authDisplayName: nil,
            isAnonymous: isAnonymous,
            email: email,
            phoneNumber: phoneNumber,
            providerIDs: isAnonymous ? [] : ["password"],
            creationDate: creationDate
        )
    }

    // MARK: - Missing profile

    @Test func missingProfileIsCreatedOnceAuthConfirmsTheAccount() async throws {
        var reloads = 0

        let outcome = await provisioner.provision(account()) {
            reloads += 1
            return .exists
        }

        #expect(outcome == .created)
        #expect(outcome.needsName)
        #expect(reloads == 1)
        let call = try #require(firestore.createUserCalls.first)
        #expect(firestore.createUserCalls.count == 1)
        #expect(call.user.id == "u1")
        #expect(call.user.displayName == "Player")
        #expect(call.user.friendIds.isEmpty)
        #expect(call.user.createdAt == Self.now)
        #expect(call.user.elo == 1500)
        // The email goes only to the private doc, never into the public name.
        #expect(call.email == "ada.lovelace@example.com")
    }

    @Test(arguments: newAccountNameCases)
    func newProfileNeverUsesContactDetailsAsItsName(
        isAnonymous: Bool, email: String?, phone: String?, expected: String
    ) async throws {
        _ = await provisioner.provision(account(isAnonymous: isAnonymous, email: email, phoneNumber: phone)) { .exists }

        let call = try #require(firestore.createUserCalls.first)
        #expect(call.user.displayName == expected)
        #expect(call.phoneNumber == phone)
    }

    @Test func lateProfileRecordsWhenTheAccountWasCreated() async throws {
        _ = await provisioner.provision(account(creationDate: Self.signUpDate)) { .exists }

        let call = try #require(firestore.createUserCalls.first)
        #expect(call.user.createdAt == Self.signUpDate)
    }

    @Test func deletedAccountGetsNoProfile() async {
        let outcome = await provisioner.provision(account()) { .gone }

        #expect(outcome == .accountGone)
        #expect(!outcome.needsName)
        #expect(firestore.userWriteCount == 0)
    }

    @Test func unconfirmedAccountGetsNoProfileYet() async {
        let outcome = await provisioner.provision(account()) { .unknown }

        #expect(outcome == .postponed)
        #expect(!outcome.needsName)
        #expect(firestore.userWriteCount == 0)
    }

    @Test func failedCreateIsPostponed() async {
        firestore.userWriteError = URLError(.notConnectedToInternet)

        let outcome = await provisioner.provision(account()) { .exists }

        #expect(outcome == .postponed)
        #expect(!outcome.needsName)
    }

    // MARK: - Incomplete profile

    @Test func emptyProfileGetsOnlyTheMissingFieldsAndANamePrompt() async throws {
        // The empty doc registerFcmToken used to create.
        firestore.userDocumentsToReturn["u1"] = .incomplete(missingFields: [.displayName, .createdAt, .elo])
        var reloads = 0

        let outcome = await provisioner.provision(account()) {
            reloads += 1
            return .exists
        }

        #expect(outcome == .repaired(wroteName: true))
        #expect(outcome.needsName)
        #expect(reloads == 0)
        #expect(firestore.createUserCalls.isEmpty)
        let call = try #require(firestore.repairUserProfileCalls.first)
        #expect(firestore.repairUserProfileCalls.count == 1)
        #expect(call.id == "u1")
        #expect(call.repair == ProfileRepair(displayName: "Player", createdAt: Self.now, elo: 1500))
    }

    @Test func repairRecordsWhenTheAccountWasCreated() async throws {
        // An account from v1.1.0 whose profile was never written: "Member
        // Since" must show the sign-up date, not the day of the repair.
        firestore.userDocumentsToReturn["u1"] = .incomplete(missingFields: [.displayName, .createdAt, .elo])

        _ = await provisioner.provision(account(creationDate: Self.signUpDate)) { .exists }

        let call = try #require(firestore.repairUserProfileCalls.first)
        #expect(call.repair.createdAt == Self.signUpDate)
    }

    @Test func repairKeepsTheFieldsTheProfileHas() async throws {
        firestore.userDocumentsToReturn["u1"] = .incomplete(missingFields: [.createdAt])

        let outcome = await provisioner.provision(account()) { .exists }

        #expect(outcome == .repaired(wroteName: false))
        #expect(!outcome.needsName)
        let call = try #require(firestore.repairUserProfileCalls.first)
        #expect(call.repair == ProfileRepair(displayName: nil, createdAt: Self.now, elo: nil))
    }

    @Test func failedRepairIsPostponed() async {
        firestore.userDocumentsToReturn["u1"] = .incomplete(missingFields: [.displayName, .createdAt])
        firestore.userWriteError = URLError(.notConnectedToInternet)

        let outcome = await provisioner.provision(account()) { .exists }

        #expect(outcome == .postponed)
        #expect(!outcome.needsName)
    }

    // MARK: - Profiles left alone

    @Test func undecodableProfileIsNeverOverwritten() async {
        firestore.userDocumentsToReturn["u1"] = .undecodable
        var reloads = 0

        let outcome = await provisioner.provision(account()) {
            reloads += 1
            return .exists
        }

        #expect(outcome == .leftUndecodable)
        #expect(!outcome.needsName)
        #expect(reloads == 0)
        #expect(firestore.userWriteCount == 0)
    }

    @Test func completeProfileIsLeftAlone() async {
        firestore.usersToReturn["u1"] = TreacheryUser(
            id: "u1", displayName: "Ada", friendIds: ["f1"], createdAt: Self.now, elo: 1620
        )

        let outcome = await provisioner.provision(account()) { .exists }

        #expect(outcome == .alreadyComplete)
        #expect(!outcome.needsName)
        #expect(firestore.userWriteCount == 0)
    }

    @Test func failedReadChangesNothing() async {
        firestore.userDocumentError = URLError(.notConnectedToInternet)
        var reloads = 0

        let outcome = await provisioner.provision(account()) {
            reloads += 1
            return .exists
        }

        #expect(outcome == .postponed)
        #expect(reloads == 0)
        #expect(firestore.userWriteCount == 0)
    }
}
