import Testing
import Foundation
@testable import Treachery_iOS

/// What Game Over shows while its two listeners report, in either order.
/// It waits for both the game and its players before choosing: the results,
/// "Game Still In Progress", or the status (loading, or a failure with a way
/// home).
@MainActor
struct GameOverContentTests {

    private struct ListenerError: Error {}

    private func makeGame(state: GameState) -> Game {
        Game(
            id: "game1", code: "ABCD", hostId: "u0", state: state,
            gameMode: .treachery, maxPlayers: 8, startingLife: 40,
            winningTeam: state == .finished ? "leader" : nil, playerIds: ["u0", "u1"],
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    private func makePlayers() -> [Player] {
        (0..<2).map { i in
            Player(
                id: "p\(i)", orderId: i, userId: "u\(i)", displayName: "Player \(i)",
                role: .guardian, identityCardId: nil, lifeTotal: 40,
                isEliminated: false, isUnveiled: true, joinedAt: Date(timeIntervalSince1970: 0)
            )
        }
    }

    /// Game Over's view model, on the production initializer. `initialGame`
    /// and `initialPlayers` arrive as the listeners attach.
    private func makeGameOver(initialGame: Game?, initialPlayers: [Player]) -> (GameBoardViewModel, MockFirestoreManager) {
        let firestore = MockFirestoreManager()
        if let initialGame {
            firestore.gamesToReturn[initialGame.id] = initialGame
        }
        firestore.playersToReturn = initialPlayers
        let vm = GameBoardViewModel(
            gameId: "game1",
            currentUserId: "u1",
            firestoreManager: firestore,
            cloudFunctions: MockCloudFunctions(),
            cardDatabase: CardDatabase(cards: []),
            planeDatabase: PlaneDatabase(cards: [])
        )
        return (vm, firestore)
    }

    @Test func playersAheadOfTheGameShowLoadingNotStillInProgress() {
        let (vm, firestore) = makeGameOver(initialGame: nil, initialPlayers: makePlayers())
        #expect(vm.gameOverContent == .status)
        #expect(vm.status == .loading)

        firestore.emitGame(.loaded(makeGame(state: .finished)), gameId: "game1")

        #expect(vm.gameOverContent == .results)
    }

    @Test func theGameAheadOfItsPlayersShowsLoading() {
        let (vm, firestore) = makeGameOver(initialGame: makeGame(state: .finished), initialPlayers: [])
        #expect(vm.gameOverContent == .status)
        #expect(vm.status == .loading)

        firestore.emitPlayers(.success(makePlayers()), gameId: "game1")

        #expect(vm.gameOverContent == .results)
    }

    @Test func aGameNotFinishedYetSaysSo() {
        let (vm, firestore) = makeGameOver(initialGame: makeGame(state: .inProgress), initialPlayers: makePlayers())
        #expect(vm.gameOverContent == .stillInProgress)

        firestore.emitGame(.loaded(makeGame(state: .finished)), gameId: "game1")

        #expect(vm.gameOverContent == .results)
    }

    @Test func aFailedListenerShowsTheFailure() {
        // GameStatusView offers Try Again and Back to Home for it.
        let (vm, firestore) = makeGameOver(initialGame: nil, initialPlayers: makePlayers())

        firestore.emitGame(.failed(.listenerStopped(ListenerError())), gameId: "game1")

        #expect(vm.gameOverContent == .status)
        #expect(vm.status == .failed)
    }

    @Test func aFailureAfterTheResultsReplacesThem() {
        let (vm, firestore) = makeGameOver(initialGame: makeGame(state: .finished), initialPlayers: makePlayers())
        #expect(vm.gameOverContent == .results)

        firestore.emitGame(.missing, gameId: "game1")

        #expect(vm.gameOverContent == .status)
        #expect(vm.status == .unavailable)
    }
}
