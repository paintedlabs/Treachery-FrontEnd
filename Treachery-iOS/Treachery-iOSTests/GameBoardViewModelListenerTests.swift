import Testing
import Foundation
@testable import Treachery_iOS

/// How the board (and Game Over, which shares its view model) reacts to each
/// listener outcome. Uses the production initializer, so the listeners are
/// really attached, and drives them through the mock.
@MainActor
struct GameBoardViewModelListenerTests {

    private struct ListenerError: Error {}

    // MARK: - Helpers

    private func makeGame(
        state: GameState = .inProgress,
        gameMode: GameMode = .treachery
    ) -> Game {
        Game(
            id: "game1", code: "ABCD", hostId: "u0", state: state,
            gameMode: gameMode, maxPlayers: 8, startingLife: 40,
            winningTeam: nil, playerIds: ["u0", "u1"],
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    private func makePlayers(life: Int = 40) -> [Player] {
        (0..<2).map { i in
            Player(
                id: "p\(i)", orderId: i, userId: "u\(i)", displayName: "Player \(i)",
                role: .guardian, identityCardId: nil, lifeTotal: life,
                isEliminated: false, isUnveiled: false, joinedAt: Date()
            )
        }
    }

    /// `initialGame` is delivered as soon as the listener attaches; nil
    /// leaves the board waiting for whatever the test emits.
    private func makeBoard(
        initialGame: Game?,
        players: [Player]
    ) -> (GameBoardViewModel, MockFirestoreManager) {
        let mockFS = MockFirestoreManager()
        if let initialGame {
            mockFS.gamesToReturn[initialGame.id] = initialGame
        }
        mockFS.playersToReturn = players
        let vm = GameBoardViewModel(
            gameId: "game1",
            currentUserId: "u1",
            firestoreManager: mockFS,
            cloudFunctions: MockCloudFunctions(),
            cardDatabase: CardDatabase(cards: []),
            planeDatabase: PlaneDatabase(cards: [])
        )
        return (vm, mockFS)
    }

    // MARK: - Loading and ready

    @Test func snapshotsMakeTheBoardReady() {
        let (vm, _) = makeBoard(initialGame: makeGame(), players: makePlayers())
        #expect(vm.status == .ready)
        #expect(vm.players.count == 2)
    }

    @Test func waitsForTheGameSnapshot() {
        let (vm, _) = makeBoard(initialGame: nil, players: makePlayers())
        #expect(vm.status == .loading)
    }

    @Test func waitsForPlayersBeforeShowingTheBoard() {
        let (vm, _) = makeBoard(initialGame: makeGame(), players: [])
        #expect(vm.status == .loading)
    }

    // MARK: - Missing game

    @Test func gameAlreadyGoneOnOpenIsUnavailable() {
        // Used to spin on "Loading game..." forever: a missing first snapshot
        // was ignored.
        let (vm, mockFS) = makeBoard(initialGame: nil, players: [])
        mockFS.emitGame(.missing, gameId: "game1")
        #expect(vm.status == .unavailable)
    }

    @Test func gameDeletedMidGameIsUnavailable() {
        let (vm, mockFS) = makeBoard(initialGame: makeGame(), players: makePlayers())
        mockFS.emitGame(.missing, gameId: "game1")
        #expect(vm.status == .unavailable)
    }

    // MARK: - Failures

    @Test func gameListenerFailureShowsFailedNotUnavailable() {
        let (vm, mockFS) = makeBoard(initialGame: makeGame(), players: makePlayers())
        mockFS.emitGame(.failed(.listenerStopped(ListenerError())), gameId: "game1")
        #expect(vm.status == .failed)
    }

    @Test func playersListenerFailureShowsFailed() {
        // e.g. permission denied once the user is no longer in player_ids.
        let (vm, mockFS) = makeBoard(initialGame: makeGame(), players: makePlayers())
        mockFS.emitPlayers(.failure(.listenerStopped(ListenerError())), gameId: "game1")
        #expect(vm.status == .failed)
    }

    @Test func deletionWinsOverTheDeniedPlayersRead() {
        let (vm, mockFS) = makeBoard(initialGame: makeGame(), players: makePlayers())
        mockFS.emitPlayers(.failure(.listenerStopped(ListenerError())), gameId: "game1")
        mockFS.emitGame(.missing, gameId: "game1")
        #expect(vm.status == .unavailable)
    }

    @Test func failureSticksUntilRetry() {
        let game = makeGame()
        let (vm, mockFS) = makeBoard(initialGame: game, players: makePlayers())
        mockFS.emitPlayers(.failure(.listenerStopped(ListenerError())), gameId: "game1")
        mockFS.emitGame(.loaded(game), gameId: "game1")
        #expect(vm.status == .failed)
    }

    @Test func retryReattachesBothListeners() {
        let (vm, mockFS) = makeBoard(initialGame: makeGame(), players: makePlayers())
        mockFS.emitGame(.failed(.listenerStopped(ListenerError())), gameId: "game1")

        vm.retry()

        #expect(vm.status == .ready)
        #expect(mockFS.activeGameListenerCount(gameId: "game1") == 1)
        #expect(mockFS.activePlayersListenerCount(gameId: "game1") == 1)
    }

    // MARK: - Unreadable data

    @Test func unreadableGameNeedsANewerVersion() {
        // Not "Couldn't Load": retrying would read the same document again.
        let (vm, mockFS) = makeBoard(initialGame: makeGame(), players: makePlayers())
        mockFS.emitGame(.failed(.unreadable(ListenerError())), gameId: "game1")
        #expect(vm.status == .needsNewerVersion)

        vm.retry()
        #expect(vm.status == .needsNewerVersion)
    }

    @Test func unreadablePlayerNeedsANewerVersion() {
        // One seat this build can't read used to vanish from the board
        // silently; now the whole board asks for an update.
        let (vm, mockFS) = makeBoard(initialGame: makeGame(), players: makePlayers())
        mockFS.emitPlayers(.failure(.unreadable(ListenerError())), gameId: "game1")
        #expect(vm.status == .needsNewerVersion)
    }

    @Test func precedenceIsDeletionThenUnreadableThenFailure() {
        let (vm, mockFS) = makeBoard(initialGame: makeGame(), players: makePlayers())
        mockFS.emitPlayers(.failure(.listenerStopped(ListenerError())), gameId: "game1")
        mockFS.emitGame(.failed(.unreadable(ListenerError())), gameId: "game1")
        #expect(vm.status == .needsNewerVersion)

        mockFS.emitGame(.missing, gameId: "game1")
        mockFS.emitPlayers(.failure(.unreadable(ListenerError())), gameId: "game1")
        #expect(vm.status == .unavailable)
    }

    // MARK: - Unknown state and mode

    @Test func unknownStateNeedsANewerVersion() {
        let (vm, _) = makeBoard(initialGame: makeGame(state: .unknown("paused")), players: makePlayers())
        #expect(vm.status == .needsNewerVersion)
    }

    @Test func unknownModeNeedsANewerVersion() {
        let (vm, _) = makeBoard(initialGame: makeGame(gameMode: .unknown("archenemy")), players: makePlayers())
        #expect(vm.status == .needsNewerVersion)
    }

    // MARK: - Later snapshots

    @Test func laterPlayersSnapshotUpdatesTheBoard() {
        let (vm, mockFS) = makeBoard(initialGame: makeGame(), players: makePlayers(life: 40))
        mockFS.emitPlayers(.success(makePlayers(life: 33)), gameId: "game1")
        #expect(vm.players.map(\.lifeTotal) == [33, 33])
    }

    @Test func laterGameSnapshotUpdatesTheBoard() {
        let (vm, mockFS) = makeBoard(initialGame: makeGame(), players: makePlayers())
        mockFS.emitGame(.loaded(makeGame(state: .finished)), gameId: "game1")
        #expect(vm.isGameFinished)
        #expect(vm.status == .ready)
    }
}
