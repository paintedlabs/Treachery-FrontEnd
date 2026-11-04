import Testing
import Foundation
@testable import Treachery_iOS

/// What VoiceOver reads out as the board changes. Once the game is over,
/// Game Over covers the board, and nothing on the board is read out over
/// the results.
@MainActor
struct GameBoardAnnouncementTests {

    private static let eliminated = "You've been eliminated. You can keep watching, or use Leave Game at the bottom of the screen."

    private let failure = GameBoardViewModel.LifeChangeFailure(playerId: "p1", playerName: "Player 1", kind: .unconfirmed)

    @Test func anEliminationIsReadOutWhileTheGameGoesOn() {
        let board = LifeBoard()
        board.snapshot([0, 40, 40])

        #expect(board.vm.seat == .spectating)
        #expect(board.vm.announcement(forSeatChangeFrom: .playing, to: .spectating) == Self.eliminated)
    }

    @Test func anEliminationThatArrivesWithTheFinishedGameIsNotReadOut() throws {
        // The signed-in player's own death ends the game. Game Over has no
        // Leave Game to point them to.
        let board = LifeBoard()
        #expect(board.vm.seat == .playing)
        try board.finishGame()
        board.snapshot([0, 40, 40])

        #expect(board.vm.seat == .spectating)
        #expect(board.vm.announcement(forSeatChangeFrom: .playing, to: .spectating) == nil)
    }

    @Test func theBoardsOtherNewsIsReadOutWhileTheGameGoesOn() {
        let board = LifeBoard()

        #expect(board.vm.announcement(forError: "Couldn't end the game.") == "Couldn't end the game.")
        #expect(board.vm.announcements(forFailuresFrom: [], to: [failure]).map(\.message) == [failure.message])
        #expect(board.vm.announcement(for: .revealing) == "Identity revealed")
        #expect(board.vm.announcement(for: .failed(message: "Already unveiled.")) == "Already unveiled.")
    }

    @Test func nothingElseIsReadOutOnceTheGameIsOver() throws {
        // A roll or a forfeit that raced the end, refused with "Game is not
        // in progress.", or an end game whose reply was lost.
        let board = LifeBoard()
        try board.finishGame()

        #expect(board.vm.announcement(forError: "Game is not in progress.") == nil)
        #expect(board.vm.announcements(forFailuresFrom: [], to: [failure]).isEmpty)
        #expect(board.vm.announcement(for: .revealing) == nil)
        #expect(board.vm.announcement(for: .failed(message: "Game is not in progress.")) == nil)
        #expect(!board.vm.announcesBoardChanges)
    }
}
