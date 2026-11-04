import Testing
import Foundation
@testable import Treachery_iOS

/// Life changes to several players failing close together, as when the
/// device is offline and someone deals damage around the table. Each total
/// goes back, so each needs explaining: one failure mustn't replace another.
@MainActor
struct SeveralLifeChangeFailuresTests {

    /// Fails `amount` on the player while the device is offline.
    private func fail(_ playerId: String, by amount: Int, on board: LifeBoard) async {
        board.functions.errorToThrow = URLError(.notConnectedToInternet)
        board.vm.adjustLife(for: playerId, by: amount)
        await board.endDebounces()
        await board.finishSends()
    }

    @Test(.timeLimit(.minutes(1)))
    func failuresForSeveralPlayersAreAllNamed() async {
        let board = LifeBoard()

        await fail("p1", by: -2, on: board)
        await fail("p2", by: -2, on: board)

        #expect(board.vm.lifeChangeFailures.map(\.playerId) == ["p1", "p2"])
        #expect(board.vm.lifeChangeMessage == "Couldn't update life for Player 1 and Player 2. Check your connection and try again.")
        #expect(board.shown("p1") == 40)
        #expect(board.shown("p2") == 40)
    }

    @Test(.timeLimit(.minutes(1)))
    func changingOnePlayerAgainClearsOnlyTheirFailure() async {
        let board = LifeBoard()
        await fail("p1", by: -2, on: board)
        await fail("p2", by: -2, on: board)

        board.vm.adjustLife(for: "p1", by: -2)

        #expect(board.vm.lifeChangeMessage == "Couldn't update Player 2's life. Check your connection and try again.")
    }

    @Test(.timeLimit(.minutes(1)))
    func eachPlayerKeepsTheirOwnWording() async throws {
        // Player 1's -2 shows in a snapshot before its call fails, so it
        // can't be confirmed; Player 2's never shows.
        let board = LifeBoard()
        let gate = board.holdCalls()
        board.functions.errorToThrow = URLError(.notConnectedToInternet)
        board.vm.adjustLife(for: "p1", by: -2)
        await board.endDebounces()
        let send = try board.send(for: "p1")
        await gate.waitForCall(from: send)
        board.snapshot([40, 38, 40])
        gate.release()
        await send.value

        await fail("p2", by: -2, on: board)

        #expect(board.vm.lifeChangeMessage == """
            Couldn't confirm Player 1's life change. Check the total before changing it again. \
            Couldn't update Player 2's life. Check your connection and try again.
            """)
    }

    @Test(.timeLimit(.minutes(1)))
    func aPlayerChangedAgainWhoFailsAgainComesLast() async {
        let board = LifeBoard()
        await fail("p1", by: -2, on: board)
        await fail("p2", by: -2, on: board)
        board.functions.errorToThrow = CallableRefusal(reason: .failedPrecondition, message: "Game is not in progress.")
        board.vm.adjustLife(for: "p1", by: -1)
        await board.endDebounces()
        await board.finishSends()

        #expect(board.vm.lifeChangeFailures.map(\.playerId) == ["p2", "p1"])
        #expect(board.vm.lifeChangeMessage == """
            Couldn't update Player 2's life. Check your connection and try again. \
            Couldn't update Player 1's life. Game is not in progress.
            """)
    }

    @Test(.timeLimit(.minutes(1)))
    func aPlayersTwoFailedChangesAreExplainedAsOne() async throws {
        // The -1 held behind the -3 goes out once the -3 fails, and fails
        // too. Both were sent from 40, so a later 36 would show both landed.
        let board = LifeBoard()
        let gate = board.holdCalls()
        board.functions.errorToThrow = URLError(.notConnectedToInternet)
        let send = try await board.holdTapBehindAChangeInFlight()

        gate.release()
        await send.value
        await board.finishSends()

        #expect(gate.arrivals == 2)
        #expect(board.vm.lifeChangeFailures == [GameBoardViewModel.LifeChangeFailure(
            playerId: "p0", playerName: "Player 0", kind: .notApplied(baseline: 40, amount: -4)
        )])
        #expect(board.vm.lifeChangeMessage == "Couldn't update Player 0's life. Check your connection and try again.")
        #expect(board.shown() == 40)

        board.snapshot([36, 40, 40])
        #expect(board.vm.lifeChangeFailures.isEmpty)
    }
}

/// The banner and the announcements, worked out from the failures alone.
struct LifeChangeFailureWordingTests {

    private typealias Failure = GameBoardViewModel.LifeChangeFailure

    private let sarah = Failure(playerId: "p0", playerName: "Sarah", kind: .notApplied(baseline: 40, amount: -2))
    private let tom = Failure(playerId: "p1", playerName: "Tom", kind: .notApplied(baseline: 40, amount: -2))
    private let ana = Failure(playerId: "p2", playerName: "Ana", kind: .notApplied(baseline: 40, amount: -2))

    @Test func noFailuresMeansNoBanner() {
        #expect(Failure.bannerMessage(for: []) == nil)
    }

    @Test func threeNamesReadAsAList() {
        #expect(Failure.bannerMessage(for: [sarah, tom, ana])
            == "Couldn't update life for Sarah, Tom, and Ana. Check your connection and try again.")
    }

    @Test func refusalsForTheSameReasonShareASentence() {
        let refused = [sarah, tom].map {
            Failure(playerId: $0.playerId, playerName: $0.playerName, kind: .refused(reason: "Game is not in progress."))
        }
        #expect(Failure.bannerMessage(for: refused) == "Couldn't update life for Sarah and Tom. Game is not in progress.")
    }

    @Test func severalUnconfirmedChangesShareASentence() {
        let unconfirmed = [sarah, tom].map { Failure(playerId: $0.playerId, playerName: $0.playerName, kind: .unconfirmed) }
        #expect(Failure.bannerMessage(for: unconfirmed)
            == "Couldn't confirm the life changes for Sarah and Tom. Check their totals before changing them again.")
    }

    @Test func aFirstFailureIsReadOutStraightAway() {
        #expect(Failure.announcements(from: [], to: [sarah]) == [
            Failure.Announcement(message: "Couldn't update Sarah's life. Check your connection and try again.", interrupts: true),
        ])
    }

    @Test func laterFailuresWaitTheirTurn() {
        // Each is read by itself, and none cuts off the one before.
        #expect(Failure.announcements(from: [], to: [sarah, tom]) == [
            Failure.Announcement(message: sarah.message, interrupts: true),
            Failure.Announcement(message: tom.message, interrupts: false),
        ])
        #expect(Failure.announcements(from: [sarah], to: [sarah, tom]) == [
            Failure.Announcement(message: tom.message, interrupts: false),
        ])
    }

    @Test func aRevisedFailureIsReadOutAgain() {
        let sarahUnconfirmed = Failure(playerId: "p0", playerName: "Sarah", kind: .unconfirmed)
        #expect(Failure.announcements(from: [sarah, tom], to: [sarahUnconfirmed, tom]) == [
            Failure.Announcement(message: sarahUnconfirmed.message, interrupts: false),
        ])
    }

    @Test func aFailureThatGoesIsNotReadOut() {
        #expect(Failure.announcements(from: [sarah, tom], to: [tom]).isEmpty)
    }

    // MARK: - A player's failures, one after another

    private func sarah(_ kind: Failure.Kind) -> Failure {
        Failure(playerId: "p0", playerName: "Sarah", kind: kind)
    }

    @Test func twoChangesThatNeverShowedAddUp() {
        let both = sarah(.notApplied(baseline: 40, amount: -3)).followed(by: sarah(.notApplied(baseline: 40, amount: -1)))
        #expect(both == sarah(.notApplied(baseline: 40, amount: -4)))
    }

    /// Earlier and later kinds that leave the board unable to vouch for the
    /// total.
    static let unconfirmedSequences: [(GameBoardViewModel.LifeChangeFailure.Kind, GameBoardViewModel.LifeChangeFailure.Kind)] = [
        (.unconfirmed, .notApplied(baseline: 40, amount: -1)),
        (.notApplied(baseline: 40, amount: -1), .unconfirmed),
        (.refused(reason: "Game is not in progress."), .unconfirmed),
        // Sent from different totals: their sum says nothing.
        (.notApplied(baseline: 40, amount: -1), .notApplied(baseline: 37, amount: -1)),
    ]

    @Test(arguments: unconfirmedSequences)
    func anythingUnconfirmedLeavesTheTotalUnconfirmed(
        earlier: GameBoardViewModel.LifeChangeFailure.Kind,
        later: GameBoardViewModel.LifeChangeFailure.Kind
    ) {
        #expect(sarah(earlier).followed(by: sarah(later)).kind == .unconfirmed)
    }

    @Test func otherwiseTheLaterFailureSaysWhatHappened() {
        let refused = sarah(.refused(reason: "Game is not in progress."))
        #expect(sarah(.notApplied(baseline: 40, amount: -1)).followed(by: refused) == refused)
        #expect(refused.followed(by: sarah(.notApplied(baseline: 40, amount: -1))) == sarah(.notApplied(baseline: 40, amount: -1)))
    }
}
