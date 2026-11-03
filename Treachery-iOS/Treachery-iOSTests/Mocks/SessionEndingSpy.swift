import Foundation
@testable import Treachery_iOS

/// Spy for the session: counts sign-outs, can be told to fail, and can run a
/// hook at the moment of signing out, so a test can check what already happened.
final class SessionEndingSpy: SessionEnding {
    private(set) var endSessionCallCount = 0
    var errorToThrow: Error?
    /// Runs on every `endSession()` call, before any error is thrown.
    var whileEndingSession: (() -> Void)?

    func endSession() throws {
        endSessionCallCount += 1
        whileEndingSession?()
        if let errorToThrow { throw errorToThrow }
    }
}
