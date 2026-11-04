import Testing
import Foundation
@testable import Treachery_iOS

/// Which callable errors count as the server turning a request down. The
/// lobby acts on these: leave() takes "not found" as already gone, and the
/// server's message is shown to the player.
struct CallableRefusalTests {

    /// Shaped like the errors the Functions SDK throws: its domain, a
    /// FunctionsErrorCode raw value, and the server's message (or the SDK's
    /// placeholder when there wasn't one) as the description.
    private func functionsError(code: Int, message: String) -> NSError {
        NSError(domain: "com.firebase.functions", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    @Test func notFoundWithTheServersMessageIsARefusal() throws {
        let refusal = try #require(CallableRefusal(functionsError(code: 5, message: "You are not in this game.")))
        #expect(refusal.reason == .notFound)
        #expect(refusal.message == "You are not in this game.")
    }

    @Test func failedPreconditionWithTheServersMessageIsARefusal() throws {
        let refusal = try #require(CallableRefusal(functionsError(code: 9, message: "This game is full.")))
        #expect(refusal.reason == .failedPrecondition)
        #expect(refusal.message == "This game is full.")
    }

    @Test func bareStatusWithoutTheServersMessageIsNotARefusal() {
        // E.g. a 404 for a function that isn't deployed, which leave() must
        // not take as "already gone".
        #expect(CallableRefusal(functionsError(code: 5, message: "NOT FOUND")) == nil)
        #expect(CallableRefusal(functionsError(code: 9, message: "FAILED PRECONDITION")) == nil)
    }

    @Test func otherFailuresAreNotRefusals() {
        #expect(CallableRefusal(functionsError(code: 14, message: "UNAVAILABLE")) == nil)
        #expect(CallableRefusal(functionsError(code: 7, message: "Only the host can start the game.")) == nil)
        #expect(CallableRefusal(URLError(.notConnectedToInternet)) == nil)
    }
}
