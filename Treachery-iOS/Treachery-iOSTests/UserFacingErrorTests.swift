import Testing
import Foundation
@testable import Treachery_iOS

// The literal domains and codes the Firebase SDKs report, so these cases also
// check that the mapper matches what arrives at runtime:
// FunctionsErrorDomain, FirestoreErrorDomain and AuthErrors.domain, and the
// FunctionsErrorCode, FirestoreErrorCode.Code and AuthErrorCode raw values.
private let functionsDomain = "com.firebase.functions"
private let firestoreDomain = "FIRFirestoreErrorDomain"
private let authDomain = "FIRAuthErrorDomain"

private func error(_ domain: String, _ code: Int, _ description: String? = nil) -> NSError {
    NSError(domain: domain, code: code, userInfo: description.map { [NSLocalizedDescriptionKey: $0] } ?? [:])
}

@Suite("User-facing error messages")
struct UserFacingErrorTests {

    @Test("The network's errors", arguments: [
        (URLError(.notConnectedToInternet), UserFacingError.offline),
        (URLError(.dataNotAllowed), .offline),
        (URLError(.internationalRoamingOff), .offline),
        (URLError(.networkConnectionLost), .serverUnreachable),
        (URLError(.cannotFindHost), .serverUnreachable),
        (URLError(.cannotConnectToHost), .serverUnreachable),
        (URLError(.dnsLookupFailed), .serverUnreachable),
        (URLError(.timedOut), .timedOut),
        (URLError(.badServerResponse), .unknown),
    ])
    func networkErrors(error: URLError, expected: UserFacingError) {
        #expect(UserFacingError(error) == expected)
    }

    /// Cloud Functions passes network failures through as NSErrors.
    @Test func networkErrorsArrivingAsNSErrorsAreRecognized() {
        #expect(UserFacingError(error(NSURLErrorDomain, NSURLErrorNotConnectedToInternet)) == .offline)
        #expect(UserFacingError(error(NSURLErrorDomain, NSURLErrorTimedOut)) == .timedOut)
    }

    @Test("Cloud Functions' errors never show the server's developer text", arguments: [
        (error(functionsDomain, 14, "UNAVAILABLE"), UserFacingError.serverUnreachable),
        (error(functionsDomain, 4, "DEADLINE EXCEEDED"), .timedOut),
        (error(functionsDomain, 16, "Must be signed in."), .notSignedIn),
        (error(functionsDomain, 7, "Only the recipient can accept."), .notPermitted),
        (error(functionsDomain, 5, "Friend request not found."), .notFound),
        (error(functionsDomain, 8, "Could not allocate a unique game code."), .tooManyRequests),
        (error(functionsDomain, 13, "INTERNAL"), .unknown),
        (error(functionsDomain, 3, "gameId is required."), .unknown),
    ])
    func functionsErrors(error: NSError, expected: UserFacingError) {
        #expect(UserFacingError(error) == expected)
    }

    /// acceptFriendRequest's refusal, the only one the callables this mapper
    /// serves send, is developer text; players get a sentence for it.
    @Test func acceptingAnAnsweredRequestIsSaidPlainly() {
        let refusal = error(functionsDomain, 9, "  Request is not pending. ")

        #expect(UserFacingError(refusal) == .requestAlreadyAnswered)
    }

    /// The server's refusal text is written for developers, so any refusal
    /// not translated, from a game callable say, never reaches players.
    @Test("Any other failed-precondition gets a plain sentence, never the server's text", arguments: [
        error(functionsDomain, 9, "Using own deck."),
        error(functionsDomain, 9, "Leader is always visible."),
        error(functionsDomain, 9, "This game is full."),
        error(functionsDomain, 9, "FAILED PRECONDITION"),
        error(functionsDomain, 9, "   "),
        error(functionsDomain, 9),
    ])
    func otherFailedPreconditions(error: NSError) {
        #expect(UserFacingError(error) == .unknown)
    }

    @Test("Firestore's errors never show its developer text", arguments: [
        (error(firestoreDomain, 14, "Failed to get document because the client is offline."), UserFacingError.serverUnreachable),
        (error(firestoreDomain, 4, "Deadline expired before operation could complete."), .timedOut),
        (error(firestoreDomain, 16, "The request does not have valid authentication credentials."), .notSignedIn),
        (error(firestoreDomain, 7, "Missing or insufficient permissions."), .notPermitted),
        (error(firestoreDomain, 5, "No document to update"), .notFound),
        (error(firestoreDomain, 8, "Quota exceeded."), .tooManyRequests),
        // Firestore's failed-precondition is developer text: a missing index.
        (error(firestoreDomain, 9, "The query requires an index. You can create it here: https://console.firebase.google.com"), .unknown),
        (error(firestoreDomain, 13, "Internal error"), .unknown),
    ])
    func firestoreErrors(error: NSError, expected: UserFacingError) {
        #expect(UserFacingError(error) == expected)
    }

    @Test("Firebase Auth's errors on the sign-in screens", arguments: [
        (17_020, UserFacingError.serverUnreachable),   // networkError
        (17_008, .invalidEmail),                       // invalidEmail
        (17_034, .invalidEmail),                       // missingEmail
        (17_004, .incorrectEmailOrPassword),           // invalidCredential
        (17_009, .incorrectEmailOrPassword),           // wrongPassword
        (17_011, .noAccountForEmail),                  // userNotFound
        (17_007, .emailAlreadyInUse),                  // emailAlreadyInUse
        (17_026, .weakPassword),                       // weakPassword
        (17_005, .accountDisabled),                    // userDisabled
        (17_010, .tooManyRequests),                    // tooManyRequests
        (17_042, .invalidPhoneNumber),                 // invalidPhoneNumber
        (17_044, .incorrectCode),                      // invalidVerificationCode
        (17_051, .expiredCode),                        // sessionExpired
        (17_052, .tooManyCodes),                       // quotaExceeded
        (17_058, .verificationIncomplete),             // webContextCancelled
        (17_006, .signInMethodUnavailable),            // operationNotAllowed
        (17_017, .notSignedIn),                        // invalidUserToken
        (17_995, .unknown),                            // keychainError
        (17_999, .unknown),                            // internalError
    ])
    func authErrors(code: Int, expected: UserFacingError) {
        #expect(UserFacingError(error(authDomain, code, "Firebase's own description")) == expected)
    }

    @Test("Anything else gets a plain sentence, never its own description", arguments: [
        error("test", 1, "remove failed"),
        error("CloudFunctions", -1, "Invalid createGame response"),
        AccountDeletionError.unexpectedResponse,
        CancellationError(),
    ] as [any Error])
    func unrecognizedErrors(error: any Error) {
        #expect(UserFacingError(error) == .unknown)
    }

    @Test func notBeingSignedInIsSaidPlainly() {
        #expect(UserFacingError(FirebaseManager.AuthError.notAuthenticated) == .notSignedIn)
    }

    /// An offline read with nothing cached says the server couldn't be
    /// reached, as Firestore's own offline failure does.
    @Test func readsThatFoundNothingTrustworthySayWhy() {
        #expect(UserFacingError(FirestoreReadError.nothingCachedOffline) == .serverUnreachable)
        #expect(UserFacingError(FirestoreReadError.profileUnavailable) == .unknown)
    }

    @Test func anAlreadyMappedErrorIsKept() {
        let mapped = UserFacingError(message: "This game is full.")

        #expect(UserFacingError(mapped) == mapped)
    }
}
