//
//  UserFacingError.swift
//  Treachery-iOS
//

import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// A failure as players should read it: a short, plain sentence that says
/// what went wrong and what to do next.
///
/// `init(_:)` is the one place that turns errors from Firebase Auth,
/// Firestore, Cloud Functions and the network into these sentences. Screens
/// show `message` and never an error's `localizedDescription`, which for
/// Firebase is developer text such as "Missing or insufficient permissions."
/// or "DEADLINE EXCEEDED". A screen that needs to say what failed puts its
/// own short lead in front, such as "Your name wasn't saved."
struct UserFacingError: Error, Equatable {
    let message: String
}

// MARK: - Mapping

extension UserFacingError {
    /// The sentence for `error`, or `unknown` for an error not recognized.
    ///
    /// Text written by the server never reaches players as is. Of Cloud
    /// Functions, this mapper serves two callables today: acceptFriendRequest
    /// and removeFriend. A `failed-precondition` is the server refusing an
    /// action the current state doesn't allow, and across functions/ its text
    /// is written for developers, such as "Request is not pending.", "Using
    /// own deck." or "Leader is always visible." So the refusals those two
    /// callables send are translated in `functionsRefusals`, and any other
    /// gets `unknown`. A screen that starts using this mapper for another
    /// callable adds that callable's refusals there first.
    init(_ error: any Error) {
        self = Self.recognized(error) ?? .unknown
    }

    /// This failure as a screen that needs the user's profile says it while
    /// the profile setup is in `state`. On hold after a deletion whose
    /// outcome is unknown, a profile that isn't set up stays so until the
    /// app relaunches, whatever the connection, so it says that, and that
    /// Try Again checks whether the account was deleted.
    func whileProfileSetup(is state: ProfileSetupState) -> Self {
        guard self == .profileNotSetUp, state == .onHoldUntilRelaunch else { return self }
        return .profileSetupOnHold
    }

    private static func recognized(_ error: any Error) -> Self? {
        switch error {
        case let error as Self:
            return error
        case is FirebaseManager.AuthError:
            return .notSignedIn
        case let error as FirestoreReadError:
            return firestoreReadErrors[error]
        case let error as URLError:
            return urlErrors[error.code]
        default:
            return recognizedFirebaseError(error as NSError)
        }
    }

    /// Firebase's errors, which arrive as NSErrors told apart by domain.
    private static func recognizedFirebaseError(_ error: NSError) -> Self? {
        switch error.domain {
        case FunctionsErrorDomain:
            guard let code = FunctionsErrorCode(rawValue: error.code) else { return nil }
            if code == .failedPrecondition {
                return refusal(describedAs: error.userInfo[NSLocalizedDescriptionKey] as? String)
            }
            return functionsErrors[code]
        case FirestoreErrorDomain:
            return FirestoreErrorCode.Code(rawValue: error.code).flatMap { firestoreErrors[$0] }
        case AuthErrors.domain:
            return AuthErrorCode(rawValue: error.code).flatMap { authErrors[$0] }
        default:
            return nil
        }
    }

    /// The sentence for a Cloud Functions refusal, found by the server's
    /// text. Only the refusals in `functionsRefusals` are recognized; any
    /// other text, a blank one, or the SDK's "FAILED PRECONDITION" stand-in
    /// for none, isn't.
    private static func refusal(describedAs serverText: String?) -> Self? {
        guard let serverText = serverText?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return functionsRefusals[serverText]
    }

    // Lookup tables rather than switches: the codes not listed fall back to
    // `unknown`, and each table reads as the decision it records.

    /// The refusals (`failed-precondition`) of the callables this mapper
    /// serves, by the server's text (functions/src/callables/users.js).
    /// removeFriend sends none.
    private static let functionsRefusals: [String: Self] = [
        // acceptFriendRequest, for a request accepted or declined already:
        // on another device, say, or by an earlier tap whose answer was lost.
        "Request is not pending.": .requestAlreadyAnswered,
    ]

    private static let urlErrors: [URLError.Code: Self] = [
        .notConnectedToInternet: .offline,
        .dataNotAllowed: .offline,
        .internationalRoamingOff: .offline,
        .networkConnectionLost: .serverUnreachable,
        .cannotFindHost: .serverUnreachable,
        .cannotConnectToHost: .serverUnreachable,
        .dnsLookupFailed: .serverUnreachable,
        .timedOut: .timedOut,
    ]

    /// An offline read with nothing cached reads the same as Firestore's own
    /// offline failure, `unavailable`. The user's own profile is almost
    /// always unreadable because it couldn't be set up yet, offline say.
    private static let firestoreReadErrors: [FirestoreReadError: Self] = [
        .nothingCachedOffline: .serverUnreachable,
        .profileUnavailable: .profileNotSetUp,
    ]

    /// A failed-precondition never gets here: see `functionsRefusals`.
    private static let functionsErrors: [FunctionsErrorCode: Self] = [
        .unavailable: .serverUnreachable,
        .deadlineExceeded: .timedOut,
        .unauthenticated: .notSignedIn,
        .permissionDenied: .notPermitted,
        .notFound: .notFound,
        .resourceExhausted: .tooManyRequests,
    ]

    /// Firestore reports a read it couldn't make, online or not, as
    /// `unavailable`. Its failed-precondition is developer text (a missing
    /// index), so it gets `unknown` like the other codes not listed.
    private static let firestoreErrors: [FirestoreErrorCode.Code: Self] = [
        .unavailable: .serverUnreachable,
        .deadlineExceeded: .timedOut,
        .unauthenticated: .notSignedIn,
        .permissionDenied: .notPermitted,
        .notFound: .notFound,
        .resourceExhausted: .tooManyRequests,
    ]

    /// The codes the sign-in screens can meet. With email enumeration
    /// protection on, Firebase reports a wrong password and an unknown email
    /// alike, as `invalidCredential`, so that reads as "incorrect" without
    /// saying which. `userNotFound` comes only with protection off.
    private static let authErrors: [AuthErrorCode: Self] = [
        .networkError: .serverUnreachable,
        .webNetworkRequestFailed: .serverUnreachable,
        .tooManyRequests: .tooManyRequests,
        .invalidEmail: .invalidEmail,
        .missingEmail: .invalidEmail,
        .invalidCredential: .incorrectEmailOrPassword,
        .wrongPassword: .incorrectEmailOrPassword,
        .userNotFound: .noAccountForEmail,
        .emailAlreadyInUse: .emailAlreadyInUse,
        .weakPassword: .weakPassword,
        .userDisabled: .accountDisabled,
        .invalidPhoneNumber: .invalidPhoneNumber,
        .missingPhoneNumber: .invalidPhoneNumber,
        .invalidVerificationCode: .incorrectCode,
        .sessionExpired: .expiredCode,
        .invalidVerificationID: .expiredCode,
        .quotaExceeded: .tooManyCodes,
        .captchaCheckFailed: .verificationIncomplete,
        .webContextCancelled: .verificationIncomplete,
        .operationNotAllowed: .signInMethodUnavailable,
        .adminRestrictedOperation: .signInMethodUnavailable,
        .invalidUserToken: .notSignedIn,
        .userTokenExpired: .notSignedIn,
    ]
}

// MARK: - Messages

extension UserFacingError {
    static let offline = Self(message: String(
        localized: "You're offline. Check your connection and try again.",
        comment: "Error shown when the device has no internet connection"
    ))
    static let serverUnreachable = Self(message: String(
        localized: "Couldn't reach the server. Check your connection and try again.",
        comment: "Error shown when the server couldn't be reached, for example on a poor connection"
    ))
    static let timedOut = Self(message: String(
        localized: "The server took too long to respond. Try again.",
        comment: "Error shown when a request timed out"
    ))
    static let notSignedIn = Self(message: String(
        localized: "You're not signed in. Sign in and try again.",
        comment: "Error shown when the server no longer accepts the user's sign-in"
    ))
    static let notPermitted = Self(message: String(
        localized: "You don't have permission to do that.",
        comment: "Error shown when the server refused an action for this user"
    ))
    static let notFound = Self(message: String(
        localized: "That's no longer available.",
        comment: "Error shown when what the user acted on no longer exists, such as a withdrawn friend request"
    ))
    static let tooManyRequests = Self(message: String(
        localized: "Too many attempts. Wait a moment and try again.",
        comment: "Error shown when the user or the app made too many requests in a short time"
    ))
    static let unknown = Self(message: String(
        localized: "Something went wrong. Try again.",
        comment: "Error shown when nothing more specific is known"
    ))
    static let profileNotSetUp = Self(message: String(
        localized: "Your profile isn't set up yet. Check your connection, then try again.",
        comment: "Error shown when the user's own profile can't be read, usually because it couldn't be created while offline"
    ))
    static let profileSetupOnHold = Self(message: String(
        localized: "Your account's deletion couldn't be confirmed. Try again to check, or close and reopen the app to finish setting up your profile.",
        comment: "Error shown on Profile and Friends when a failed account deletion may have gone through, so the profile isn't set up yet"
    ))

    // Signing in

    static let invalidEmail = Self(message: String(
        localized: "Enter a valid email address.",
        comment: "Sign-in error for a malformed or missing email address"
    ))
    static let incorrectEmailOrPassword = Self(message: String(
        localized: "The email or password is incorrect.",
        comment: "Sign-in error for a wrong password or an email with no account"
    ))
    static let noAccountForEmail = Self(message: String(
        localized: "There's no account with that email.",
        comment: "Error shown when no account uses the email entered"
    ))
    static let emailAlreadyInUse = Self(message: String(
        localized: "An account with that email already exists. Sign in instead.",
        comment: "Sign-up error when the email already has an account"
    ))
    static let weakPassword = Self(message: String(
        localized: "That password is too weak. Choose a stronger one.",
        comment: "Sign-up error when the password doesn't meet the requirements"
    ))
    static let accountDisabled = Self(message: String(
        localized: "This account has been disabled.",
        comment: "Sign-in error for a disabled account"
    ))
    static let invalidPhoneNumber = Self(message: String(
        localized: "Enter a valid phone number, including the country code.",
        comment: "Phone sign-in error for a malformed or missing phone number"
    ))
    static let incorrectCode = Self(message: String(
        localized: "That code isn't right. Check it and try again.",
        comment: "Phone sign-in error for a wrong verification code"
    ))
    static let expiredCode = Self(message: String(
        localized: "That code has expired. Send a new one.",
        comment: "Phone sign-in error when the verification code is no longer valid"
    ))
    static let tooManyCodes = Self(message: String(
        localized: "Too many codes have been sent. Try again later.",
        comment: "Phone sign-in error when the text message quota is used up"
    ))
    static let verificationIncomplete = Self(message: String(
        localized: "Verification didn't finish. Try again.",
        comment: "Phone sign-in error when the robot check was cancelled or failed"
    ))
    static let signInMethodUnavailable = Self(message: String(
        localized: "This way of signing in isn't available right now.",
        comment: "Sign-in error when the sign-in method is turned off"
    ))

    // Friends

    static let requestAlreadyAnswered = Self(message: String(
        localized: "That request was already answered.",
        comment: "Error shown when accepting a friend request that was already accepted or declined"
    ))
}
