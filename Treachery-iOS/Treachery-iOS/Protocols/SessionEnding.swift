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
}
