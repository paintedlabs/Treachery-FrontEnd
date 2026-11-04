import Testing
import Foundation
@testable import Treachery_iOS

@MainActor
struct LobbyViewModelActionTests {

    // MARK: - Helpers

    private func makeMockSetup(
        game: Game? = nil,
        players: [Player] = []
    ) -> (MockFirestoreManager, MockCloudFunctions) {
        let mockFS = MockFirestoreManager()
        let mockCF = MockCloudFunctions()

        let defaultGame = Game(
            id: "game1", code: "ABCD", hostId: "host1", state: .waiting,
            gameMode: .treachery, maxPlayers: 8, startingLife: 40,
            winningTeam: nil, playerIds: ["host1"],
            createdAt: Date()
        )

        mockFS.gamesToReturn = [(game ?? defaultGame)].reduce(into: [:]) { $0[$1.id] = $1 }
        mockFS.playersToReturn = players

        return (mockFS, mockCF)
    }

    private func makePlayers(count: Int, currentUserId: String = "u0") -> [Player] {
        (0..<count).map { i in
            Player(
                id: "p\(i)", orderId: i, userId: "u\(i)", displayName: "Player \(i)",
                role: nil, identityCardId: nil, lifeTotal: 40,
                isEliminated: false, isUnveiled: false, joinedAt: Date()
            )
        }
    }

    private func yieldToMainActor() async {
        await Task.yield()
        await Task.yield()
    }

    // MARK: - leave

    @Test func leaveCallsCloudFunctionAndReportsSuccess() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: false,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        let didLeave = await vm.leave()
        #expect(didLeave)
        #expect(mockCF.leaveGameCalls == ["game1"])
    }

    @Test func failedLeaveKeepsPlayerInLobby() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        mockCF.errorToThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "leave failed"])
        let vm = LobbyViewModel(
            gameId: "game1", isHost: false,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        vm.currentUserId = "u1"

        let didLeave = await vm.leave()

        // The view navigates home only on success, so the player stays put…
        #expect(!didLeave)
        #expect(vm.game?.id == "game1")
        #expect(vm.pendingAction == nil)
        #expect(vm.errorMessage == "Couldn't leave the lobby. Check your connection and try again.")
        // …and the lobby keeps updating.
        #expect(mockFS.activeGameListenerCount(gameId: "game1") == 1)
        #expect(mockFS.activePlayersListenerCount(gameId: "game1") == 1)
        mockFS.emitPlayers(.success(makePlayers(count: 5)), gameId: "game1")
        #expect(vm.players.count == 5)
    }

    @Test func failedLeaveOffersAWayHomeThatKeepsTheSeat() async {
        // Leave is the lobby's only way out, and offline it keeps failing.
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        mockCF.errorToThrow = URLError(.notConnectedToInternet)
        let vm = LobbyViewModel(
            gameId: "game1", isHost: false,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        #expect(!vm.offersHomeWithoutLeaving)

        _ = await vm.leave()

        #expect(vm.offersHomeWithoutLeaving)
        #expect(vm.requestFailure == .leave("Couldn't leave the lobby. Check your connection and try again."))
    }

    @Test func leaveCountsAsDoneWhenTheServerFindsNothingToLeave() async {
        // The seat (or the whole lobby) is already gone, for example because
        // an earlier leave got through and only its reply was lost.
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        mockCF.errorToThrow = CallableRefusal(reason: .notFound, message: "You are not in this game.")
        let vm = LobbyViewModel(
            gameId: "game1", isHost: false,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )

        let didLeave = await vm.leave()

        #expect(didLeave)
        #expect(vm.requestFailure == nil)
        #expect(vm.isLeaving)
        #expect(mockFS.activeGameListenerCount(gameId: "game1") == 0)
        #expect(mockFS.activePlayersListenerCount(gameId: "game1") == 0)
    }

    @Test func leaveWhoseReplyWasLostEndsNotInTheGame() async {
        // The leave went through, but its reply never arrived, so leave()
        // reports a failure and listens again. The restarted players read
        // is refused, and the lobby says the player is out instead of
        // blaming the connection.
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        mockCF.errorToThrow = URLError(.networkConnectionLost)
        let vm = LobbyViewModel(
            gameId: "game1", isHost: false,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )

        let didLeave = await vm.leave()
        let denied = NSError(domain: "FIRFirestoreErrorDomain", code: 7)
        mockFS.emitPlayers(.failure(.accessDenied(denied)), gameId: "game1")

        #expect(!didLeave)
        #expect(vm.status == .notInGame)
    }

    @Test(.timeLimit(.minutes(1)))
    func leaveRefusedBecauseTheGameStartedStillReachesTheBoard() async {
        // The host starts while we leave: the server refuses the leave, and
        // the restarted listener reports the game in progress, which is what
        // moves the lobby on to the board.
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let gate = CallGate()
        mockCF.leaveGameGate = gate
        mockCF.errorToThrow = CallableRefusal(
            reason: .failedPrecondition, message: "Can only leave a game in the waiting state."
        )
        let vm = LobbyViewModel(
            gameId: "game1", isHost: false,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )

        let leaving = Task { await vm.leave() }
        await gate.waitForCall(from: leaving)
        mockFS.gamesToReturn["game1"] = Game(
            id: "game1", code: "ABCD", hostId: "host1", state: .inProgress,
            gameMode: .treachery, maxPlayers: 8, startingLife: 40,
            winningTeam: nil, playerIds: ["host1"],
            createdAt: Date()
        )
        gate.release()

        #expect(await leaving.value == false)
        #expect(vm.isGameStarted)
        #expect(vm.errorMessage == "The game has already started, so you can't leave the lobby.")
    }

    @Test(.timeLimit(.minutes(1)))
    func leaveIgnoresRepeatTapWhileInFlight() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let gate = CallGate()
        mockCF.leaveGameGate = gate
        let vm = LobbyViewModel(
            gameId: "game1", isHost: false,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )

        let first = Task { await vm.leave() }
        await gate.waitForCall(from: first)
        #expect(vm.isLeaving)
        // The gate holds only the first call, so a repeat that slipped
        // through would be counted below rather than wait forever.
        let repeatTap = await vm.leave()
        gate.release()

        #expect(repeatTap == false)
        #expect(await first.value)
        #expect(gate.arrivals == 1)
        #expect(mockCF.leaveGameCalls == ["game1"])
    }

    @Test func leaveClearsErrorBeforeCall() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: false,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        vm.currentUserId = "u1"
        mockFS.errorToThrow = NSError(domain: "test", code: 1)
        await vm.updatePlayerColor("#FF0000")
        #expect(vm.errorMessage != nil)

        _ = await vm.leave()
        // errorMessage should be nil (cleared before call, no new error)
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Host leave confirmation

    private func makeHostedLobby(players: [Player]) -> LobbyViewModel {
        let game = Game(
            id: "game1", code: "ABCD", hostId: "u0", state: .waiting,
            gameMode: .treachery, maxPlayers: 8, startingLife: 40,
            winningTeam: nil, playerIds: players.map(\.userId),
            createdAt: Date()
        )
        let (mockFS, mockCF) = makeMockSetup(game: game, players: players)
        return LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
    }

    @Test func hostLeavingPassesHostToTheEarliestRemainingSeat() {
        // Out of seat order on purpose: the server promotes by order_id.
        let players = makePlayers(count: 3).reversed()
        let vm = makeHostedLobby(players: Array(players))
        vm.currentUserId = "u0"
        #expect(vm.hostLeaveOutcome == .passesHost(to: "Player 1"))
    }

    @Test func hostLeavingAloneClosesTheLobby() {
        let vm = makeHostedLobby(players: makePlayers(count: 1))
        vm.currentUserId = "u0"
        #expect(vm.hostLeaveOutcome == .closesLobby)
    }

    @Test func nonHostLeavesWithoutConfirmation() {
        let vm = makeHostedLobby(players: makePlayers(count: 3))
        vm.currentUserId = "u1"
        #expect(vm.hostLeaveOutcome == nil)
    }

    // MARK: - startGame re-entrancy

    @Test(.timeLimit(.minutes(1)))
    func startGameIgnoresRepeatTapWhileInFlight() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let gate = CallGate()
        mockCF.startGameGate = gate
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )

        let first = Task { await vm.startGame() }
        await gate.waitForCall(from: first)
        #expect(vm.isStartingGame)
        // As for leave: a repeat that slipped through would be counted, not hang.
        await vm.startGame()
        gate.release()
        await first.value

        #expect(gate.arrivals == 1)
        #expect(mockCF.startGameCalls == ["game1"])
    }

    @Test func startGameStaysPendingUntilTheBoardTakesOver() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await vm.startGame()
        // The in-progress snapshot moves the lobby to the board; until then
        // Start must not be tappable again.
        #expect(vm.isStartingGame)
        await vm.startGame()
        #expect(mockCF.startGameCalls == ["game1"])
    }

    @Test func refusedStartShowsTheServersReason() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        mockCF.errorToThrow = CallableRefusal(reason: .failedPrecondition, message: "Not enough players.")
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )

        await vm.startGame()

        #expect(vm.errorMessage == "Not enough players.")
        #expect(vm.pendingAction == nil)
    }

    @Test func failedStartCanBeTriedAgain() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        mockCF.errorToThrow = NSError(domain: "test", code: 1)
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )

        await vm.startGame()
        #expect(vm.pendingAction == nil)
        #expect(vm.errorMessage == "Couldn't start the game. Check your connection and try again.")

        mockCF.errorToThrow = nil
        await vm.startGame()
        #expect(mockCF.startGameCalls == ["game1"])
        #expect(vm.errorMessage == nil)
    }

    // MARK: - updatePlayerColor

    @Test func updatePlayerColorCallsFirestoreManager() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await yieldToMainActor()
        vm.currentUserId = "u0"
        await vm.updatePlayerColor("#FF0000")
        #expect(mockFS.updatePlayerColorCalls.count == 1)
        #expect(mockFS.updatePlayerColorCalls.first?.color == "#FF0000")
    }

    @Test func updatePlayerColorDoesNothingWithoutCurrentPlayer() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        // currentUserId is nil by default
        await vm.updatePlayerColor("#FF0000")
        #expect(mockFS.updatePlayerColorCalls.isEmpty)
    }

    // MARK: - updateCommanderName

    @Test func updateCommanderNameCallsFirestoreManager() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await yieldToMainActor()
        vm.currentUserId = "u0"
        await vm.updateCommanderName("Krenko, Mob Boss")
        #expect(mockFS.updateCommanderNameCalls.count == 1)
        #expect(mockFS.updateCommanderNameCalls.first?.name == "Krenko, Mob Boss")
    }

    @Test func updateCommanderNameNilForEmptyString() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await yieldToMainActor()
        vm.currentUserId = "u0"
        await vm.updateCommanderName(nil)
        #expect(mockFS.updateCommanderNameCalls.count == 1)
        #expect(mockFS.updateCommanderNameCalls.first?.name == nil)
    }

    // MARK: - updateGameSettings

    @Test func updateGameSettingsPassesMaxTraitorRarity() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await yieldToMainActor()
        vm.currentUserId = "host1"
        await vm.updateGameSettings(maxTraitorRarity: "rare")
        #expect(mockCF.updateGameSettingsCalls.count == 1)
        #expect(mockCF.updateGameSettingsCalls.first?.gameId == "game1")
        #expect(mockCF.updateGameSettingsCalls.first?.maxTraitorRarity == "rare")
        // Confirmed change is mirrored locally for the settings UI
        #expect(vm.maxTraitorRarity == .rare)
    }

    @Test func updateGameSettingsDoesNothingWhenNotHost() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: false,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await yieldToMainActor()
        vm.currentUserId = "u0"
        await vm.updateGameSettings(maxTraitorRarity: "rare")
        #expect(mockCF.updateGameSettingsCalls.isEmpty)
        #expect(vm.maxTraitorRarity == .special)
    }

    @Test func updateGameSettingsKeepsLocalRarityOnFailure() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        mockCF.errorToThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "settings failed"])
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await yieldToMainActor()
        vm.currentUserId = "host1"
        await vm.updateGameSettings(maxTraitorRarity: "rare")
        #expect(vm.maxTraitorRarity == .special)
        #expect(vm.errorMessage == "Couldn't change the game settings. Check your connection and try again.")
    }

    @Test func refusedSettingsChangeShowsTheServersReason() async {
        // Retrying can't fix this one, so it mustn't say to check the connection.
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        mockCF.errorToThrow = CallableRefusal(
            reason: .failedPrecondition, message: "Cannot set max players below the current lobby size."
        )
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        vm.currentUserId = "host1"

        await vm.updateGameSettings(maxPlayers: 3)

        #expect(vm.errorMessage == "Cannot set max players below the current lobby size.")
    }

    @Test func nextRequestClearsTheLastFailure() async {
        // The banner sits at the end of the scrolling content, just above
        // the pinned buttons; it mustn't outlive the problem it describes.
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        vm.currentUserId = "u0"
        mockFS.errorToThrow = NSError(domain: "test", code: 1)
        await vm.updatePlayerColor("#FF0000")
        #expect(vm.errorMessage == "Couldn't change your color. Check your connection and try again.")

        mockFS.errorToThrow = nil
        await vm.updatePlayerColor("#00FF00")

        #expect(vm.errorMessage == nil)
    }

    // MARK: - Commander name while leaving

    @Test(.timeLimit(.minutes(1)))
    func commanderNameIsNotSavedWhileLeaving() async {
        // Leaving takes the lobby off screen, which flushes the commander
        // name; a seat that is going away has nothing to name.
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let gate = CallGate()
        mockCF.leaveGameGate = gate
        let vm = LobbyViewModel(
            gameId: "game1", isHost: false,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        vm.currentUserId = "u1"
        vm.commanderNameDraft = "Atraxa"

        let leaving = Task { await vm.leave() }
        await gate.waitForCall(from: leaving)
        await vm.saveCommanderName()
        gate.release()
        _ = await leaving.value
        await vm.saveCommanderName()

        #expect(mockFS.updateCommanderNameCalls.isEmpty)
    }

    // MARK: - Game Disbanding

    @Test func startGameDoesNothingWhenNotHost() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: false,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await vm.startGame()
        #expect(mockCF.startGameCalls.isEmpty)
    }
}
