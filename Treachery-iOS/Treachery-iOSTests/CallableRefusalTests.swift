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

    @Test func invalidArgumentWithTheServersMessageIsARefusal() throws {
        // A server older than this app refusing a starting life it offers.
        let refusal = try #require(CallableRefusal(functionsError(code: 3, message: "Invalid starting life value.")))
        #expect(refusal.reason == .invalidArgument)
        #expect(refusal.message == "Invalid starting life value.")
    }

    @Test func bareStatusWithoutTheServersMessageIsNotARefusal() {
        // E.g. a 404 for a function that isn't deployed, which leave() must
        // not take as "already gone".
        #expect(CallableRefusal(functionsError(code: 5, message: "NOT FOUND")) == nil)
        #expect(CallableRefusal(functionsError(code: 9, message: "FAILED PRECONDITION")) == nil)
        #expect(CallableRefusal(functionsError(code: 3, message: "INVALID ARGUMENT")) == nil)
    }

    // MARK: - What the screens show

    /// What CloudFunctions throws for `error`; see its callFunction.
    private func thrown(_ error: NSError) -> any Error {
        CallableRefusal(error) ?? error
    }

    @Test(arguments: [
        (9, "Game is not in progress."),
        (3, "Invalid starting life value."),
    ])
    func theServersSentenceExplainsARefusal(code: Int, message: String) {
        #expect(CallableRefusal.explanation(of: thrown(functionsError(code: code, message: message))) == message)
    }

    @Test(arguments: [
        (9, "FAILED PRECONDITION"),
        (3, "INVALID ARGUMENT"),
    ])
    func aBareCodeExplainsNothing(code: Int, placeholder: String) {
        // The SDK puts the code's name where the server's sentence would be.
        #expect(CallableRefusal.explanation(of: thrown(functionsError(code: code, message: placeholder))) == nil)
    }

    @Test func aMissingGameExplainsNothing() {
        // The screens say that in their own words.
        #expect(CallableRefusal.explanation(of: thrown(functionsError(code: 5, message: "Game not found."))) == nil)
    }

    @Test func otherFailuresAreNotRefusals() {
        #expect(CallableRefusal(functionsError(code: 14, message: "UNAVAILABLE")) == nil)
        #expect(CallableRefusal(functionsError(code: 7, message: "Only the host can start the game.")) == nil)
        #expect(CallableRefusal(URLError(.notConnectedToInternet)) == nil)
    }
}
