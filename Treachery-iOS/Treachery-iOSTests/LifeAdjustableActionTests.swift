import Testing
import SwiftUI
@testable import Treachery_iOS

/// VoiceOver's swipe up or down on a life total. It has to change the total
/// exactly as the + and − buttons do: by 1, through the same debounce, and
/// only while the signed-in player can change totals.
@MainActor
struct LifeAdjustableActionTests {

    @Test(.timeLimit(.minutes(1)))
    func swipingUpAddsOneLikePlus() async {
        let board = LifeBoard()

        board.vm.adjustLife(for: "p1", .increment)
        #expect(board.shown("p1") == 41)

        await board.endDebounces()
        await board.finishSends()
        #expect(board.functions.adjustLifeCalls.map { "\($0.playerId) \($0.amount)" } == ["p1 1"])
    }

    @Test(.timeLimit(.minutes(1)))
    func swipingDownTakesOneLikeMinus() async {
        let board = LifeBoard()

        board.vm.adjustLife(for: "p1", .decrement)
        #expect(board.shown("p1") == 39)

        await board.endDebounces()
        await board.finishSends()
        #expect(board.functions.adjustLifeCalls.map { "\($0.playerId) \($0.amount)" } == ["p1 -1"])
    }

    @Test(.timeLimit(.minutes(1)))
    func quickSwipesGoOutTogetherLikeTaps() async {
        let board = LifeBoard()

        board.vm.adjustLife(for: "p2", .decrement)
        board.vm.adjustLife(for: "p2", .decrement)
        board.vm.adjustLife(for: "p2", .increment)
        board.vm.adjustLife(for: "p2", .decrement)

        await board.endDebounces()
        await board.finishSends()
        #expect(board.functions.adjustLifeCalls.map(\.amount) == [-2])
        #expect(board.shown("p2") == 38)
    }

    @Test func aSpectatorsSwipeChangesNothing() {
        // The signed-in player, Player 0, is out.
        let board = LifeBoard(lifeTotals: [0, 40, 40])

        board.vm.adjustLife(for: "p1", .increment)

        #expect(board.shown("p1") == 40)
        #expect(board.vm.lifeChangeDebounces.isEmpty)
    }
}
