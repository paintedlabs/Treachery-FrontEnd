import Testing
import Foundation
@testable import Treachery_iOS

/// adjustLife's payload parsing. The board settles a change that another
/// device cancelled out only by the `newLife` it reads here, so a parse that
/// quietly read nil would leave that change on screen until the echo timeout.
/// Every board test goes through MockCloudFunctions, which skips this parse.
struct AdjustLifeResultTests {

    /// Shaped as the Functions SDK hands over gameplay.js's return value:
    /// FunctionsSerializer decodes the JSON into an NSMutableDictionary of
    /// NSNumber and NSNull.
    private func serverPayload(_ entries: [String: Any]) -> Any {
        NSMutableDictionary(dictionary: entries)
    }

    @Test func readsNewLifeFromTheServersResponse() {
        let payload = serverPayload([
            "newLife": NSNumber(value: 37), "eliminated": NSNumber(value: false), "winner": NSNull(),
        ])
        #expect(AdjustLifeResult(payload: payload).newLife == 37)
    }

    @Test func readsAResponseThatEliminatedThePlayer() {
        let payload = serverPayload([
            "newLife": NSNumber(value: 0), "eliminated": NSNumber(value: true), "winner": "leader",
        ])
        #expect(AdjustLifeResult(payload: payload).newLife == 0)
    }

    @Test func responseWithoutNewLifeReadsAsNil() {
        let payload = serverPayload(["eliminated": NSNumber(value: false), "winner": NSNull()])
        #expect(AdjustLifeResult(payload: payload).newLife == nil)
    }

    @Test func nonDictionaryPayloadReadsAsNil() {
        #expect(AdjustLifeResult(payload: NSNull()).newLife == nil)
        #expect(AdjustLifeResult(payload: NSNumber(value: 37)).newLife == nil)
        #expect(AdjustLifeResult(payload: nil).newLife == nil)
    }
}
