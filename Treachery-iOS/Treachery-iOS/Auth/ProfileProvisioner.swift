//
//  ProfileProvisioner.swift
//  Treachery-iOS
//

import Foundation
import FirebaseAuth
import os

/// The signed-in Firebase Auth account, reduced to what profile provisioning
/// and analytics read. Tests can build one; FirebaseAuth's `User` they can't.
struct SignedInAccount: Equatable {
    let uid: String
    /// The name Firebase Auth holds. The app never sets one, so it's
    /// normally nil.
    let authDisplayName: String?
    let isAnonymous: Bool
    /// Contact details from Firebase Auth. They are stored only in the
    /// owner-only `users/{uid}/private/data`, never on the public profile.
    let email: String?
    let phoneNumber: String?
    /// The account's sign-in providers, such as "password" or "phone".
    let providerIDs: [String]
    /// When Firebase Auth created the account, if it says. A profile
    /// created or repaired after sign-up records this as `created_at`, so
    /// "Member Since" shows the day the user joined, not the day of the
    /// repair.
    let creationDate: Date?

    /// The public name a new profile starts with until the user picks one:
    /// Auth's display name if it has one, else "Guest" or "Player".
    ///
    /// Never the email or phone number: every signed-in user can read
    /// `users/{uid}`, and the name is copied into lobbies and notifications.
    /// The name prompt still offers the email's local part, which the user
    /// sees and can edit before saving.
    var initialDisplayName: String {
        if let authDisplayName = authDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !authDisplayName.isEmpty {
            return authDisplayName
        }
        return isAnonymous ? "Guest" : "Player"
    }

    /// How the account signs in, for the `auth_method` analytics property.
    var authMethod: AuthMethod {
        if isAnonymous { return .guest }
        return providerIDs.contains(PhoneAuthProvider.id) ? .phone : .email
    }
}

extension SignedInAccount {
    init(_ user: User) {
        self.init(
            uid: user.uid,
            authDisplayName: user.displayName,
            isAnonymous: user.isAnonymous,
            email: user.email,
            phoneNumber: user.phoneNumber,
            providerIDs: user.providerData.map { $0.providerID },
            creationDate: user.metadata.creationDate
        )
    }
}

/// The values of the `auth_method` analytics user property.
enum AuthMethod: String {
    case guest
    case phone
    case email
}

/// Makes sure the signed-in account has a usable public profile, without
/// ever overwriting, resurrecting or wiping one.
///
/// Each state of `users/{uid}` (`UserDocument`) gets its own treatment:
/// - Missing: create it, but only once Firebase Auth confirms the account
///   still exists. A profile deleted along with its account, on another
///   device or on this one before a sign-out that then failed, must not come
///   back.
/// - Incomplete: write only the missing `display_name`, `created_at` and
///   `elo`, never `friend_ids`. A placeholder name written here gets the name
///   prompt, as for a new account.
/// - Undecodable: leave it alone. It is logged where it is read.
/// - Complete: nothing to do.
@MainActor
struct ProfileProvisioner {

    /// What provisioning did.
    enum Outcome: Equatable {
        /// The profile was already complete.
        case alreadyComplete
        /// A new profile was created with a placeholder name.
        case created
        /// The missing fields were filled in. `wroteName` says whether a
        /// placeholder name was one of them.
        case repaired(wroteName: Bool)
        /// The profile exists but can't be decoded. Nothing was written.
        case leftUndecodable
        /// Firebase Auth says the account no longer exists. Nothing was
        /// written; the caller signs out.
        case accountGone
        /// The profile couldn't be read or written, or the account couldn't
        /// be confirmed (offline, say). Nothing changed; the next sign-in or
        /// launch tries again.
        case postponed

        /// Whether the profile's name is a placeholder the user should
        /// replace, as for a new account.
        var needsName: Bool {
            switch self {
            case .created: true
            case .repaired(let wroteName): wroteName
            case .alreadyComplete, .leftUndecodable, .accountGone, .postponed: false
            }
        }
    }

    private let firestore: FirestoreManaging
    private let now: () -> Date

    private static let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "Profile")

    /// - Parameter now: The time a new or repaired profile records as
    ///   `created_at` when Firebase Auth doesn't say when the account was
    ///   created.
    init(firestore: FirestoreManaging, now: @escaping () -> Date = Date.init) {
        self.firestore = firestore
        self.now = now
    }

    /// Provisions `account`'s profile.
    /// - Parameter reloadAccount: Asks Firebase Auth whether the account
    ///   still exists. Called only when there is no profile.
    func provision(
        _ account: SignedInAccount,
        reloadAccount: () async -> AccountStatus
    ) async -> Outcome {
        let document: UserDocument
        do {
            document = try await firestore.getUserDocument(id: account.uid)
        } catch {
            Self.logger.error("Couldn't read the profile: \(String(describing: error), privacy: .private)")
            return .postponed
        }

        switch document {
        case .complete:
            return .alreadyComplete
        case .undecodable:
            // A profile this build can't read may be one a newer client
            // wrote; writing anything over it could destroy it.
            return .leftUndecodable
        case .incomplete(let missingFields):
            return await repair(account, missingFields: missingFields)
        case .missing:
            return await createIfAccountExists(account, reloadAccount: reloadAccount)
        }
    }

    private func repair(_ account: SignedInAccount, missingFields: Set<ProfileField>) async -> Outcome {
        let repair = ProfileRepair(
            displayName: missingFields.contains(.displayName) ? account.initialDisplayName : nil,
            createdAt: missingFields.contains(.createdAt) ? memberSince(account) : nil,
            elo: missingFields.contains(.elo) ? TreacheryUser.startingElo : nil
        )
        do {
            try await firestore.repairUserProfile(id: account.uid, with: repair)
        } catch {
            Self.logger.error("Couldn't repair an incomplete profile: \(String(describing: error), privacy: .private)")
            return .postponed
        }
        Self.logger.notice("Repaired an incomplete profile")
        return .repaired(wroteName: repair.displayName != nil)
    }

    private func createIfAccountExists(
        _ account: SignedInAccount,
        reloadAccount: () async -> AccountStatus
    ) async -> Outcome {
        switch await reloadAccount() {
        case .exists:
            break
        case .gone:
            Self.logger.notice("No profile, and Firebase Auth says the account is gone; not creating one")
            return .accountGone
        case .unknown:
            Self.logger.notice("No profile, and the account couldn't be confirmed; not creating one yet")
            return .postponed
        }

        let profile = TreacheryUser(
            id: account.uid,
            displayName: account.initialDisplayName,
            friendIds: [],
            createdAt: memberSince(account)
        )
        do {
            try await firestore.createUser(profile, email: account.email, phoneNumber: account.phoneNumber)
        } catch {
            Self.logger.error("Couldn't create the profile: \(String(describing: error), privacy: .private)")
            return .postponed
        }
        return .created
    }

    /// The `created_at` a new or repaired profile gets: when the account was
    /// created, which can be long before the profile is written.
    private func memberSince(_ account: SignedInAccount) -> Date {
        account.creationDate ?? now()
    }
}
