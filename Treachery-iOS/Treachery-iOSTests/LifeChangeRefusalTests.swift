import Testing
import Foundation
@testable import Treachery_iOS

/// Life changes the server must refuse: to a player who is out, or once the
/// game is over. The board doesn't send them, and when the server turns one
/// down anyway the board gives its reason instead of asking for the change
/// again, which could never work.
@MainActor
struct LifeChangeRefusalTests {

    // MARK: - The server's reason

    @Test(.timeLimit(.minutes(1)))
    func aRefusalShowsTheServersReason() async {
        // The server knows Player 1 is out before this device does.
        let board = LifeBoard()
        board.functions.adjustLifeErrors = [
            CallableRefusal(reason: .failedPrecondition, message: "Player is already eliminated."),
        ]
        board.vm.adjustLife(for: "p1", by: -3)
        await board.endDebounces()
        await board.finishSends()

        #expect(board.shown("p1") == 40)
        #expect(board.vm.lifeChangeFailure?.message == "Couldn't update Player 1's life. Player is already eliminated.")
    }

    @Test(.timeLimit(.minutes(1)))
    func aRefusalIsNeverCalledUnconfirmed() async throws {
        // Someone else's change moved the total while this one was out. A
        // refused change certainly wasn't applied, so there's nothing to
        // confirm.
        let board = LifeBoard()
        let gate = board.holdCalls()
        board.functions.adjustLifeErrors = [
            CallableRefusal(reason: .failedPrecondition, message: "Game is not in progress."),
        ]
        board.vm.adjustLife(for: "p0", by: -3)
        await board.endDebounces()
        let send = try board.send()
        await gate.waitForCall(from: send)
        board.snapshot([35, 40, 40])

        gate.release()
        await send.value

        #expect(board.shown() == 35)
        #expect(board.vm.lifeChangeFailure?.message == "Couldn't update Player 0's life. Game is not in progress.")
    }

    // MARK: - Eliminated players

    @Test(.timeLimit(.minutes(1)))
    func tapsHeldBehindALethalChangeAreDropped() async throws {
        // Player 0 is at 3. A -3 is under way when one more -1 is tapped;
        // the echo then shows them eliminated.
        let board = LifeBoard(lifeTotals: [3, 40, 40])
        let gate = board.holdCalls()
        board.vm.adjustLife(for: "p0", by: -3)
        await board.endDebounces()
        let send = try board.send()
        await gate.waitForCall(from: send)
        board.vm.adjustLife(for: "p0", by: -1)
        await board.endDebounces()
        #expect(board.shown() == 0)

        board.snapshot([0, 40, 40])
        board.functions.adjustLifeNewLife = 0
        gate.release()
        await send.value
        await board.finishSends()

        // The -1 never goes out: the server would refuse it.
        #expect(board.functions.adjustLifeCalls.map(\.amount) == [-3])
        #expect(gate.arrivals == 1)
        #expect(board.vm.lifeChangeFailure == nil)
        #expect(board.shown() == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func aTapWaitingOutItsDebounceIsDroppedWhenThePlayerIsEliminated() async {
        let board = LifeBoard(lifeTotals: [2, 40, 40])
        board.vm.adjustLife(for: "p0", by: -1)
        await board.clock.waitForSleepers()

        board.snapshot([0, 40, 40]) // another device finishes them off

        #expect(board.vm.lifeChangeDebounces.isEmpty)
        #expect(board.clock.pendingDeadlines.isEmpty)
        #expect(board.vm.lifeChangeSends.isEmpty)
        #expect(board.shown() == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func eliminationClearsThatPlayersFailure() async {
        // A tap on them can't clear it any more: taps on eliminated players
        // are ignored.
        let board = LifeBoard()
        board.functions.adjustLifeErrors = [NSError(domain: "test", code: 1)]
        board.vm.adjustLife(for: "p1", by: -3)
        await board.endDebounces()
        await board.finishSends()
        #expect(board.vm.lifeChangeFailure?.playerId == "p1")

        board.snapshot([40, 0, 40])

        #expect(board.vm.lifeChangeFailure == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func aRefusalForAPlayerAlreadyShownOutIsNotReported() async throws {
        let board = LifeBoard()
        let gate = board.holdCalls()
        board.functions.adjustLifeErrors = [
            CallableRefusal(reason: .failedPrecondition, message: "Player is already eliminated."),
        ]
        board.vm.adjustLife(for: "p1", by: 2)
        await board.endDebounces()
        let send = try board.send(for: "p1")
        await gate.waitForCall(from: send)
        board.snapshot([40, 0, 40]) // another device eliminated them first

        gate.release()
        await send.value

        #expect(board.vm.lifeChangeFailure == nil)
        #expect(board.shown("p1") == 0)
    }

    // MARK: - A finished game

    @Test(.timeLimit(.minutes(1)))
    func leavingAFinishedGameSendsNothing() async throws {
        // Game Over replacing the board is what makes it go away.
        let board = LifeBoard()
        board.vm.adjustLife(for: "p0", by: -2)
        try board.finishGame()

        let sends = board.vm.sendPendingLifeChanges()

        #expect(sends.isEmpty)
        #expect(board.vm.lifeChangeDebounces.isEmpty)
        #expect(board.clock.pendingDeadlines.isEmpty)
        #expect(board.functions.adjustLifeCalls.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func noChangeGoesOutOnceTheGameIsOver() async throws {
        let board = LifeBoard()
        board.vm.adjustLife(for: "p0", by: -2)
        try board.finishGame()

        await board.endDebounces()

        #expect(board.vm.lifeChangeSends.isEmpty)
        #expect(board.functions.adjustLifeCalls.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func aFailureAfterTheGameIsOverIsNotReported() async throws {
        // Game Over covers the board by then; its message would only be
        // read out over the results.
        let board = LifeBoard()
        let gate = board.holdCalls()
        board.functions.adjustLifeErrors = [
            CallableRefusal(reason: .failedPrecondition, message: "Game is not in progress."),
        ]
        board.vm.adjustLife(for: "p0", by: -2)
        await board.endDebounces()
        let send = try board.send()
        await gate.waitForCall(from: send)
        try board.finishGame()

        gate.release()
        await send.value

        #expect(board.vm.lifeChangeFailure == nil)
    }
}
