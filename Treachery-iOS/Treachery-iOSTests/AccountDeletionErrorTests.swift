import Testing
import Foundation
@testable import Treachery_iOS

// Literal values of FirebaseFunctions' FunctionsErrorDomain and FunctionsErrorCode
// (.deadlineExceeded = 4, .failedPrecondition = 9), which the test target does not link.
private let functionsErrorDomain = "com.firebase.functions"
private let deadlineExceededCode = 4
private let failedPreconditionCode = 9

/// The live `CloudFunctions.deleteAccount` relies on this mapping to tell the
/// server's in-game refusal, a timeout and a request that never left the
/// device apart from every other failure.
@Suite("deleteAccount callable error mapping")
struct AccountDeletionErrorTests {

    @Test func failedPreconditionBecomesInProgressGameWithTheServerMessage() {
        let message = "You're in a game that's still in progress. You can delete your account once that game ends."
        let callableError = NSError(
            domain: functionsErrorDomain,
            code: failedPreconditionCode,
            userInfo: [NSLocalizedDescriptionKey: message]
        )

        #expect(AccountDeletionError(callableError: callableError) == .inProgressGame(message: message))
    }

    /// The SDK reports both a 504 from the server and its own request timeout
    /// as `deadline-exceeded`.
    @Test func deadlineExceededBecomesTimedOut() {
        let callableError = NSError(
            domain: functionsErrorDomain,
            code: deadlineExceededCode,
            userInfo: [NSLocalizedDescriptionKey: "DEADLINE EXCEEDED"]
        )

        #expect(AccountDeletionError(callableError: callableError) == .timedOut)
    }

    /// The SDK gets the sign-in token before it builds the request, and these
    /// URL errors come only before a connection to the server is made:
    /// either way nothing was sent. Auth's codes 9 and 4 also show that only
    /// Functions' own codes mean a refusal or a timeout.
    @Test("A request that never left the device becomes notSent", arguments: [
        NSError(domain: "FIRAuthErrorDomain", code: 17_020, userInfo: [NSLocalizedDescriptionKey: "Network error"]),
        NSError(domain: "FIRAuthErrorDomain", code: failedPreconditionCode),
        NSError(domain: "FIRAuthErrorDomain", code: deadlineExceededCode),
        URLError(.cannotFindHost),
        URLError(.dnsLookupFailed),
        URLError(.cannotConnectToHost),
    ] as [any Error])
    func requestThatNeverLeftTheDeviceBecomesNotSent(error: any Error) {
        #expect(AccountDeletionError(callableError: error) == .notSent)
    }

    /// A connection lost once it was made may have delivered the request.
    /// So may a request that failed as offline or barred from cellular data:
    /// URLSession also reports these for a request it already wrote, when
    /// the network drops mid-request.
    @Test("Every other error is left for the caller to treat as retryable", arguments: [
        NSError(domain: functionsErrorDomain, code: 16, userInfo: [NSLocalizedDescriptionKey: "Must be signed in."]),
        NSError(domain: functionsErrorDomain, code: 13, userInfo: [NSLocalizedDescriptionKey: "INTERNAL"]),
        URLError(.networkConnectionLost),
        URLError(.notConnectedToInternet),
        URLError(.dataNotAllowed),
        URLError(.internationalRoamingOff),
    ] as [any Error])
    func otherErrorsAreNotRecognized(error: any Error) {
        #expect(AccountDeletionError(callableError: error) == nil)
    }
}

/// Success signs the device out, so only an explicit `{ success: true }` may
/// count as one. Responses are decoded with JSONSerialization, as the SDK
/// does, so booleans arrive bridged from NSNumber like they do in the app.
@Suite("deleteAccount response check")
struct DeleteAccountResponseTests {

    @Test("An explicit success is accepted", arguments: [
        #"{"success":true}"#,
        #"{"success":true,"note":"extra fields are ignored"}"#,
    ])
    func acceptsExplicitSuccess(json: String) throws {
        try CloudFunctions.validateDeleteAccountResponse(decoded(json))
    }

    @Test("Anything else is rejected", arguments: [
        "null",
        "{}",
        #"{"success":false}"#,
        #"{"success":"true"}"#,
        #"{"success":null}"#,
        #"{"ok":true}"#,
        "[true]",
        "true",
    ])
    func rejectsAnythingElse(json: String) throws {
        let response = try decoded(json)

        #expect(throws: AccountDeletionError.unexpectedResponse) {
            try CloudFunctions.validateDeleteAccountResponse(response)
        }
    }

    @Test func rejectsAMissingResponse() {
        #expect(throws: AccountDeletionError.unexpectedResponse) {
            try CloudFunctions.validateDeleteAccountResponse(nil)
        }
    }

    private func decoded(_ json: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)
    }
}
