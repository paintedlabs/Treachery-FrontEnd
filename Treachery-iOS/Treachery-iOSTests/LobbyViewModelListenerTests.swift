import Testing
import Foundation
@testable import Treachery_iOS

/// How the lobby reacts to each listener outcome. Snapshots are driven
/// through the mock's emit methods, the way the real SDK delivers them.
@MainActor
struct LobbyViewModelListenerTests {

    private struct ListenerError: Error {}

    // MARK: - Helpers

    private func makeGame(
        state: GameState = .waiting,
        gameMode: GameMode = .treachery,
        hostId: String = "host1"
    ) -> Game {
        Game(
            id: "game1", code: "ABCD", hostId: hostId, state: state,
            gameMode: gameMode, maxPlayers: 8, startingLife: 40,
            winningTeam: nil, playerIds: ["host1"],
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    private func makePlayers(count: Int, commanderName: String? = nil) -> [Player] {
        (0..<count).map { i in
            Player(
                id: "p\(i)", orderId: i, userId: "u\(i)", displayName: "Player \(i)",
                role: nil, identityCardId: nil, lifeTotal: 40,
                isEliminated: false, isUnveiled: false, joinedAt: Date(),
                commanderName: commanderName
            )
        }
    }

    /// `initialGame` is delivered as soon as the listener attaches; nil
    /// leaves the lobby waiting for whatever the test emits.
    private func makeLobby(
        initialGame: Game?,
        players: [Player] = [],
        isHost: Bool = false
    ) -> (LobbyViewModel, MockFirestoreManager) {
        let mockFS = MockFirestoreManager()
        if let initialGame {
            mockFS.gamesToReturn[initialGame.id] = initialGame
        }
        mockFS.playersToReturn = players
        let vm = LobbyViewModel(
            gameId: "game1", isHost: isHost,
            firestoreManager: mockFS, cloudFunctions: MockCloudFunctions()
        )
        return (vm, mockFS)
    }

    // MARK: - Loading and loaded

    @Test func waitsForTheFirstGameSnapshot() {
        let (vm, _) = makeLobby(initialGame: nil)
        #expect(vm.status == .loading)
        #expect(vm.game == nil)
    }

    @Test func firstSnapshotOpensTheLobby() {
        let game = makeGame()
        let (vm, _) = makeLobby(initialGame: game)
        #expect(vm.status == .loaded(game))
        #expect(vm.game == game)
    }

    // MARK: - Missing game

    @Test func gameAlreadyGoneOnOpenDisbandsTheLobby() {
        // Used to spin forever: a missing first snapshot was ignored. The
        // view shows this status to everyone, the host included.
        let (vm, mockFS) = makeLobby(initialGame: nil)
        mockFS.emitGame(.missing, gameId: "game1")
        #expect(vm.status == .disbanded)
    }

    @Test func gameDeletedWhileOpenDisbandsTheLobby() {
        let (vm, mockFS) = makeLobby(initialGame: makeGame())
        mockFS.emitGame(.missing, gameId: "game1")
        #expect(vm.status == .disbanded)
    }

    @Test func disbandedIsFinal() {
        let game = makeGame()
        let (vm, mockFS) = makeLobby(initialGame: game)
        mockFS.emitGame(.missing, gameId: "game1")
        mockFS.emitGame(.loaded(game), gameId: "game1")
        #expect(vm.status == .disbanded)
    }

    // MARK: - Finished game

    @Test func gameFinishedBeforeTheLobbyOpenedShowsItsEnd() {
        // E.g. the app was suspended for the whole game, or a stale Home
        // banner led here. Leave and Start would both be refused now.
        let (vm, _) = makeLobby(initialGame: makeGame(state: .finished), players: makePlayers(count: 4))
        #expect(vm.status == .finished)
        #expect(vm.game == nil)
        #expect(!vm.isGameStarted)
    }

    @Test func gameFinishingWhileTheLobbyIsOpenShowsItsEnd() {
        // Only the final snapshot arrives after a long suspension; there's no
        // in-progress one in between to move the lobby on to the board.
        let (vm, mockFS) = makeLobby(initialGame: makeGame(), players: makePlayers(count: 4))
        mockFS.emitGame(.loaded(makeGame(state: .finished)), gameId: "game1")
        #expect(vm.status == .finished)
    }

    @Test func retryAfterTheGameFinishedShowsItsEnd() {
        let (vm, mockFS) = makeLobby(initialGame: makeGame(), players: makePlayers(count: 4))
        mockFS.emitGame(.failed(.listenerStopped(ListenerError())), gameId: "game1")
        mockFS.gamesToReturn["game1"] = makeGame(state: .finished)

        vm.retry()

        #expect(vm.status == .finished)
    }

    // MARK: - Failures

    @Test func gameListenerFailureShowsFailedNotDisbanded() {
        let (vm, mockFS) = makeLobby(initialGame: makeGame())
        mockFS.emitGame(.failed(.listenerStopped(ListenerError())), gameId: "game1")
        #expect(vm.status == .failed)
    }

    @Test func playersListenerFailureShowsFailed() {
        let (vm, mockFS) = makeLobby(initialGame: makeGame())
        mockFS.emitPlayers(.failure(.listenerStopped(ListenerError())), gameId: "game1")
        #expect(vm.status == .failed)
    }

    @Test func deletionWinsOverTheDeniedPlayersRead() {
        // Once the game is deleted its players can't be read either; the two
        // listeners report in either order.
        let (failedFirst, failedFirstFS) = makeLobby(initialGame: makeGame())
        failedFirstFS.emitPlayers(.failure(.listenerStopped(ListenerError())), gameId: "game1")
        failedFirstFS.emitGame(.missing, gameId: "game1")
        #expect(failedFirst.status == .disbanded)

        let (missingFirst, missingFirstFS) = makeLobby(initialGame: makeGame())
        missingFirstFS.emitGame(.missing, gameId: "game1")
        missingFirstFS.emitPlayers(.failure(.listenerStopped(ListenerError())), gameId: "game1")
        #expect(missingFirst.status == .disbanded)
    }

    @Test func failureSticksUntilRetry() {
        let game = makeGame()
        let (vm, mockFS) = makeLobby(initialGame: game)
        mockFS.emitPlayers(.failure(.listenerStopped(ListenerError())), gameId: "game1")
        mockFS.emitGame(.loaded(game), gameId: "game1")
        #expect(vm.status == .failed)
    }

    @Test func retryReattachesBothListeners() {
        let game = makeGame()
        let (vm, mockFS) = makeLobby(initialGame: game, players: makePlayers(count: 2))
        mockFS.emitGame(.failed(.listenerStopped(ListenerError())), gameId: "game1")

        vm.retry()

        #expect(vm.status == .loaded(game))
        #expect(mockFS.activeGameListenerCount(gameId: "game1") == 1)
        #expect(mockFS.activePlayersListenerCount(gameId: "game1") == 1)
    }

    // MARK: - Unreadable data

    @Test func unreadableGameNeedsANewerVersion() {
        // Retrying would read the same document again, so this isn't
        // reported as a failure (which offers Retry and blames the connection).
        let (vm, mockFS) = makeLobby(initialGame: nil)
        mockFS.emitGame(.failed(.unreadable(ListenerError())), gameId: "game1")
        #expect(vm.status == .needsNewerVersion)
    }

    @Test func unreadablePlayerNeedsANewerVersion() {
        let (vm, mockFS) = makeLobby(initialGame: makeGame(), players: makePlayers(count: 2))
        mockFS.emitPlayers(.failure(.unreadable(ListenerError())), gameId: "game1")
        #expect(vm.status == .needsNewerVersion)
    }

    @Test func unreadableDataOutranksAListenerFailure() {
        let (vm, mockFS) = makeLobby(initialGame: makeGame())
        mockFS.emitPlayers(.failure(.listenerStopped(ListenerError())), gameId: "game1")
        mockFS.emitGame(.failed(.unreadable(ListenerError())), gameId: "game1")
        #expect(vm.status == .needsNewerVersion)

        vm.retry()
        #expect(vm.status == .needsNewerVersion)
    }

    @Test func deletionOutranksUnreadableData() {
        let (vm, mockFS) = makeLobby(initialGame: makeGame())
        mockFS.emitPlayers(.failure(.unreadable(ListenerError())), gameId: "game1")
        mockFS.emitGame(.missing, gameId: "game1")
        #expect(vm.status == .disbanded)
    }

    // MARK: - Unknown state and mode

    @Test func unknownStateNeedsANewerVersion() {
        let (vm, _) = makeLobby(initialGame: makeGame(state: .unknown("abandoned")))
        #expect(vm.status == .needsNewerVersion)
        #expect(!vm.isGameStarted)
    }

    @Test func unknownModeStillOpensAWaitingLobby() {
        let game = makeGame(gameMode: .unknown("archenemy"))
        let (vm, _) = makeLobby(initialGame: game)
        #expect(vm.status == .loaded(game))
    }

    // MARK: - Later snapshots

    @Test func promotionToHostEnablesStart() {
        // The live host_id decides, not the navigation flag (TQ-10).
        let (vm, mockFS) = makeLobby(
            initialGame: makeGame(hostId: "u0"),
            players: makePlayers(count: 4),
            isHost: false
        )
        vm.currentUserId = "u1"
        #expect(!vm.canStartGame)

        mockFS.emitGame(.loaded(makeGame(hostId: "u1")), gameId: "game1")

        #expect(vm.isHost)
        #expect(vm.canStartGame)
    }

    @Test func liveHostOverridesTheNavigationFlag() {
        let (vm, _) = makeLobby(
            initialGame: makeGame(hostId: "u0"),
            players: makePlayers(count: 4),
            isHost: true
        )
        vm.currentUserId = "u1"
        #expect(!vm.isHost)
        #expect(!vm.canStartGame)
    }

    @Test func playersSnapshotsKeepArriving() {
        let (vm, mockFS) = makeLobby(initialGame: makeGame(), players: makePlayers(count: 2))
        mockFS.emitPlayers(.success(makePlayers(count: 3)), gameId: "game1")
        #expect(vm.players.map(\.userId) == ["u0", "u1", "u2"])
    }

    // MARK: - Commander name (CM-8)

    @Test func commanderNameFillsFromTheFirstSnapshot() {
        let (vm, _) = makeLobby(
            initialGame: makeGame(),
            players: makePlayers(count: 2, commanderName: "Krenko, Mob Boss")
        )
        vm.currentUserId = "u1"
        #expect(vm.commanderNameDraft == "Krenko, Mob Boss")
    }

    @Test func laterSnapshotDoesNotRefillAClearedCommanderName() {
        let players = makePlayers(count: 2, commanderName: "Krenko, Mob Boss")
        let (vm, mockFS) = makeLobby(initialGame: makeGame(), players: players)
        vm.currentUserId = "u1"

        vm.commanderNameDraft = ""
        // Another player joins before the cleared name has been saved.
        mockFS.emitPlayers(.success(players + makePlayers(count: 3).suffix(1)), gameId: "game1")

        #expect(vm.commanderNameDraft == "")
    }

    @Test func commanderNameWaitsForTheCurrentUser() {
        let players = makePlayers(count: 2, commanderName: "Krenko, Mob Boss")
        let (vm, mockFS) = makeLobby(initialGame: makeGame(), players: [])
        mockFS.emitPlayers(.success(players), gameId: "game1")
        #expect(vm.commanderNameDraft == "")

        vm.currentUserId = "u1"

        #expect(vm.commanderNameDraft == "Krenko, Mob Boss")
    }

    @Test func saveCommanderNameSendsOnlyChanges() async {
        let mockFS = MockFirestoreManager()
        mockFS.gamesToReturn["game1"] = makeGame()
        mockFS.playersToReturn = makePlayers(count: 2, commanderName: "Krenko, Mob Boss")
        let vm = LobbyViewModel(
            gameId: "game1", isHost: false,
            firestoreManager: mockFS, cloudFunctions: MockCloudFunctions()
        )
        vm.currentUserId = "u1"

        await vm.saveCommanderName()
        #expect(mockFS.updateCommanderNameCalls.isEmpty)

        vm.commanderNameDraft = "Atraxa"
        await vm.saveCommanderName()
        vm.commanderNameDraft = ""
        await vm.saveCommanderName()

        #expect(mockFS.updateCommanderNameCalls.map(\.name) == ["Atraxa", nil])
    }
}
