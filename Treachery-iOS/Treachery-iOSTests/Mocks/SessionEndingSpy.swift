import Foundation
@testable import Treachery_iOS

/// Spy for the session: counts sign-outs and what account deletion tells it,
/// can be told to fail or to be a guest's, and can run a hook at the moment
/// of signing out, so a test can check what already happened.
final class SessionEndingSpy: SessionEnding {
    var isGuest = false
    private(set) var endSessionCallCount = 0
    private(set) var accountDeletionWillStartCallCount = 0
    /// What each `accountDeletionDidFail(_:)` call said, in order.
    private(set) var accountDeletionFailures: [AccountDeletionFailure] = []
    var errorToThrow: Error?
    /// Runs on every `endSession()` call, before any error is thrown.
    var whileEndingSession: (() -> Void)?

    func endSession() throws {
        endSessionCallCount += 1
        whileEndingSession?()
        if let errorToThrow { throw errorToThrow }
    }

    func accountDeletionWillStart() {
        accountDeletionWillStartCallCount += 1
    }

    func accountDeletionDidFail(_ failure: AccountDeletionFailure) {
        accountDeletionFailures.append(failure)
    }
}
