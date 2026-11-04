import Testing
import Foundation
@testable import Treachery_iOS

/// What the board says about a failed life change once a later snapshot
/// shows where the player's total went. A reply lost after the server
/// applied the change looks like any other failure, and following "try
/// again" would then apply the change twice.
@MainActor
struct FailedLifeChangeSnapshotTests {

    private let tryAgain = "Couldn't update Player 0's life. Check your connection and try again."

    /// Player 0's -3 fails before any snapshot shows it.
    private func boardWithAFailedChange() async -> LifeBoard {
        let board = LifeBoard()
        board.functions.adjustLifeErrors = [URLError(.networkConnectionLost)]
        board.vm.adjustLife(for: "p0", by: -3)
        await board.endDebounces()
        await board.finishSends()
        #expect(board.shown() == 40)
        #expect(board.vm.lifeChangeMessage == tryAgain)
        return board
    }

    @Test(.timeLimit(.minutes(1)))
    func aSnapshotShowingTheChangeLandedClearsTheMessage() async {
        let board = await boardWithAFailedChange()

        board.snapshot([37, 40, 40])

        #expect(board.vm.lifeChangeFailures.isEmpty)
        #expect(board.shown() == 37)
    }

    @Test(.timeLimit(.minutes(1)))
    func aSnapshotShowingAnotherTotalSaysTheChangeCantBeConfirmed() async {
        // Someone else's change, or this one and theirs: no way to tell.
        let board = await boardWithAFailedChange()

        board.snapshot([35, 40, 40])

        #expect(board.vm.lifeChangeMessage == "Couldn't confirm Player 0's life change. Check the total before changing it again.")
        #expect(board.shown() == 35)
    }

    @Test(.timeLimit(.minutes(1)))
    func aSnapshotThatLeavesTheTotalAloneKeepsTheMessage() async {
        let board = await boardWithAFailedChange()

        board.snapshot([40, 33, 40])

        #expect(board.vm.lifeChangeMessage == tryAgain)
    }

    @Test(.timeLimit(.minutes(1)))
    func aRefusedChangeStaysRefusedWhateverTheTotalDoes() async {
        // The server turned it down, so a move is someone else's change.
        let board = LifeBoard()
        board.functions.adjustLifeErrors = [
            CallableRefusal(reason: .failedPrecondition, message: "Game is not in progress."),
        ]
        board.vm.adjustLife(for: "p0", by: -3)
        await board.endDebounces()
        await board.finishSends()

        board.snapshot([37, 40, 40])

        #expect(board.vm.lifeChangeMessage == "Couldn't update Player 0's life. Game is not in progress.")
    }

    @Test(.timeLimit(.minutes(1)))
    func aSnapshotAfterTheGameIsOverLeavesTheMessageAsItIs() async throws {
        // Game Over covers the board by then, and the revised message would
        // only be read out over the results.
        let board = await boardWithAFailedChange()
        try board.finishGame()

        board.snapshot([35, 40, 40])

        #expect(board.vm.lifeChangeMessage == tryAgain)
    }
}

/// `LifeChangeFailure.revised(by:)` on its own.
struct LifeChangeFailureRevisionTests {

    private typealias Failure = GameBoardViewModel.LifeChangeFailure

    private func player(life: Int) -> Player {
        Player(
            id: "p0", orderId: 0, userId: "u0", displayName: "Sarah",
            role: .guardian, identityCardId: nil, lifeTotal: life,
            isEliminated: false, isUnveiled: false, joinedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func aChangeThatWouldHaveGoneBelowZeroLandedAtZero() {
        // The server stops at 0.
        let failure = Failure(playerId: "p0", playerName: "Sarah", kind: .notApplied(baseline: 2, amount: -5))
        #expect(failure.revised(by: player(life: 0)) == nil)
    }

    @Test func aMoveOffTheBaselineByAnythingElseIsUnconfirmed() {
        let failure = Failure(playerId: "p0", playerName: "Sarah", kind: .notApplied(baseline: 40, amount: 2))
        let revised = failure.revised(by: player(life: 41))
        #expect(revised?.kind == .unconfirmed)
        #expect(revised?.message == "Couldn't confirm Sarah's life change. Check the total before changing it again.")
    }

    @Test func anUnconfirmedChangeStaysUnconfirmed() {
        let failure = Failure(playerId: "p0", playerName: "Sarah", kind: .unconfirmed)
        #expect(failure.revised(by: player(life: 12)) == failure)
    }
}
