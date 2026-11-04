//
//  UserDocument.swift
//  Treachery-iOS
//

import Foundation

/// What `users/{uid}` holds, as `FirestoreManaging.getUserDocument(id:)`
/// found it.
///
/// Profile provisioning treats each state differently: only a missing profile
/// may be created, only an incomplete one repaired, and an undecodable one is
/// left exactly as it is. Reading all three as "no profile" once let a launch
/// overwrite a profile this build couldn't decode.
enum UserDocument {
    /// No document exists.
    case missing
    /// The document exists but lacks `display_name` or `created_at`, which
    /// every profile needs. One example is the empty document
    /// `registerFcmToken` used to create for an account with no profile.
    /// `missingFields` lists every `ProfileField` the document lacks, so it
    /// always contains `.displayName` or `.createdAt`.
    case incomplete(missingFields: Set<ProfileField>)
    /// The document has the fields every profile needs but can't be decoded,
    /// for example because another client wrote a shape this build doesn't
    /// know.
    case undecodable
    /// A complete profile.
    case complete(TreacheryUser)
}

/// The public-profile fields provisioning writes when it creates or repairs
/// a profile. `friend_ids` is deliberately not one: only the friend
/// callables change it, and firestore.rules (`onlyOwnNonFriendFields`)
/// rejects an owner's write that changes it together with any other field.
enum ProfileField: String, CaseIterable {
    case displayName = "display_name"
    case createdAt = "created_at"
    case elo
}

/// The values a repair writes onto an incomplete profile. Only the non-nil
/// ones are written, and nothing else on the document changes.
struct ProfileRepair: Equatable {
    var displayName: String?
    var createdAt: Date?
    var elo: Int?
}
