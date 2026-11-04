import Foundation

/// Ends the signed-in session on this device.
///
/// `AuthViewModel`, the app's single source of auth state, is the conformer,
/// so every sign-out goes through it. A client that only needs to end the
/// session (the Profile screen's Sign Out, and account deletion) depends on
/// just this, and its test double needs no Firebase types.
@MainActor
protocol SessionEnding {
    /// Whether the signed-in account is a guest's. A guest account can't be
    /// signed back into, so ending its session loses it for good.
    var isGuest: Bool { get }

    /// Signs this device out, throwing if it could not. On success the auth
    /// state listener routes the app to the signed-out screen.
    func endSession() throws

    /// Called before the server is asked to delete the signed-in account.
    /// Until the session ends, or `accountDeletionDidFail(_:)` says the
    /// server deleted nothing, nothing sets up the account's profile: the
    /// server deletes the profile before the sign-in account, and an attempt
    /// in between could create the profile again, with the email and phone
    /// number, to outlive the account.
    func accountDeletionWillStart()

    /// Called when the server didn't confirm the deletion, so this device
    /// stays signed in. Setting up the profile can go on only if `failure`
    /// says the server deleted nothing.
    func accountDeletionDidFail(_ failure: AccountDeletionFailure)
}

/// What a deletion the server didn't confirm did there, as far as this
/// device can tell.
enum AccountDeletionFailure: Equatable {
    /// None of the account was deleted: the server refused before it got
    /// that far, or the request never left this device.
    case nothingDeleted
    /// Unknown: the request timed out, or failed after it may have reached
    /// the server. The server may have stopped part-way or still be running,
    /// as between deleting the profile and deleting the sign-in account.
    case outcomeUnknown
}
