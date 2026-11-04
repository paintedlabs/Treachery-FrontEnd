import Testing
import Foundation
@testable import Treachery_iOS

@MainActor
struct LobbyViewModelTests {

    // MARK: - Helpers

    private func makeMockSetup(
        game: Game? = nil,
        players: [Player] = [],
        isHost: Bool = true
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

    private func makePlayers(count: Int) -> [Player] {
        (0..<count).map { i in
            Player(
                id: "p\(i)", orderId: i, userId: "u\(i)", displayName: "Player \(i)",
                role: nil, identityCardId: nil, lifeTotal: 40,
                isEliminated: false, isUnveiled: false, joinedAt: Date()
            )
        }
    }

    // MARK: - canStartGame

    /// Allow mock listener Tasks to dispatch on MainActor.
    private func yieldToMainActor() async {
        await Task.yield()
        await Task.yield()
    }

    @Test func canStartGameWhenHostAndEnoughPlayers() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await yieldToMainActor()
        #expect(vm.canStartGame == true)
    }

    @Test func cannotStartGameWhenNotHost() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: false,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await yieldToMainActor()
        #expect(vm.canStartGame == false)
    }

    @Test func cannotStartGameWithTooFewPlayers() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 3))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await yieldToMainActor()
        #expect(vm.canStartGame == false)
    }

    @Test func canStartNonTreacheryGameWithOnePlayer() async {
        let game = Game(
            id: "game1", code: "ABCD", hostId: "host1", state: .waiting,
            gameMode: .none, maxPlayers: 12, startingLife: 40,
            winningTeam: nil, playerIds: ["host1"],
            createdAt: Date()
        )
        let (mockFS, mockCF) = makeMockSetup(game: game, players: makePlayers(count: 1))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await yieldToMainActor()
        #expect(vm.canStartGame == true)
    }

    // MARK: - minimumPlayerCount

    @Test func minimumPlayerCountForTreachery() async {
        let (mockFS, mockCF) = makeMockSetup()
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await yieldToMainActor()
        #expect(vm.minimumPlayerCount == 4)
    }

    @Test func minimumPlayerCountForLifeTracker() async {
        let game = Game(
            id: "game1", code: "ABCD", hostId: "host1", state: .waiting,
            gameMode: .none, maxPlayers: 12, startingLife: 40,
            winningTeam: nil, playerIds: ["host1"],
            createdAt: Date()
        )
        let (mockFS, mockCF) = makeMockSetup(game: game)
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await yieldToMainActor()
        #expect(vm.minimumPlayerCount == 1)
    }

    // MARK: - startRequirement

    @Test func startRequirementExplainsTooFewPlayers() {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 3))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        #expect(vm.startRequirement == "Need at least 4 players to start")
    }

    @Test func startRequirementSingularForLifeTracker() {
        let game = Game(
            id: "game1", code: "ABCD", hostId: "host1", state: .waiting,
            gameMode: .none, maxPlayers: 8, startingLife: 40,
            winningTeam: nil, playerIds: ["host1"],
            createdAt: Date()
        )
        let (mockFS, mockCF) = makeMockSetup(game: game, players: [])
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        #expect(vm.startRequirement == "Need at least 1 player to start")
    }

    @Test func noStartRequirementOnceEnoughPlayersOrForGuests() {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let host = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        #expect(host.startRequirement == nil)

        let (guestFS, guestCF) = makeMockSetup(players: makePlayers(count: 1))
        let guest = LobbyViewModel(
            gameId: "game1", isHost: false,
            firestoreManager: guestFS, cloudFunctions: guestCF
        )
        #expect(guest.startRequirement == nil)
    }

    @Test func unknownModeCannotBeStarted() {
        // The board would show "Update Required" to everyone on this build,
        // so the host is pointed at a mode it can play instead.
        let game = Game(
            id: "game1", code: "ABCD", hostId: "host1", state: .waiting,
            gameMode: .unknown("archenemy"), maxPlayers: 8, startingLife: 40,
            winningTeam: nil, playerIds: ["host1"],
            createdAt: Date()
        )
        let (mockFS, mockCF) = makeMockSetup(game: game, players: makePlayers(count: 4))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        #expect(!vm.canStartGame)
        #expect(vm.startRequirement == "Update Treachery or choose another game mode to start")
    }

    // MARK: - smallestMaxPlayers

    @Test(arguments: [(seated: 1, smallest: 2), (seated: 5, smallest: 5), (seated: 10, smallest: 8)])
    func smallestMaxPlayersKeepsEveryoneSeated(seated: Int, smallest: Int) {
        // The server refuses a max below the lobby's size; a legacy lobby
        // with more than 8 seated is capped at 8, the highest setting.
        let game = Game(
            id: "game1", code: "ABCD", hostId: "host1", state: .waiting,
            gameMode: .none, maxPlayers: 12, startingLife: 40,
            winningTeam: nil, playerIds: (0..<seated).map { "u\($0)" },
            createdAt: Date()
        )
        let (mockFS, mockCF) = makeMockSetup(game: game)
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        #expect(vm.smallestMaxPlayers == smallest)
    }

    // MARK: - isGameStarted

    @Test func isGameStartedWhenInProgress() async {
        let game = Game(
            id: "game1", code: "ABCD", hostId: "host1", state: .inProgress,
            gameMode: .treachery, maxPlayers: 8, startingLife: 40,
            winningTeam: nil, playerIds: ["host1"],
            createdAt: Date()
        )
        let (mockFS, mockCF) = makeMockSetup(game: game)
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await yieldToMainActor()
        #expect(vm.isGameStarted == true)
    }

    @Test func isGameNotStartedWhenWaiting() async {
        let (mockFS, mockCF) = makeMockSetup()
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await yieldToMainActor()
        #expect(vm.isGameStarted == false)
    }

    // MARK: - currentPlayer

    @Test func currentPlayerFindsMatch() async {
        let players = makePlayers(count: 3)
        let (mockFS, mockCF) = makeMockSetup(players: players)
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await yieldToMainActor()
        vm.currentUserId = "u1"
        #expect(vm.currentPlayer?.userId == "u1")
    }

    @Test func currentPlayerNilWhenNoUserId() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 3))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await yieldToMainActor()
        #expect(vm.currentPlayer == nil)
    }

    // MARK: - startGame calls cloud function

    @Test func startGameCallsCloudFunction() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await vm.startGame()
        #expect(mockCF.startGameCalls == ["game1"])
    }

    @Test func startGameSetsErrorOnFailure() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        mockCF.errorToThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        let vm = LobbyViewModel(
            gameId: "game1", isHost: true,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await vm.startGame()
        // A plain sentence, never the server's or SDK's own description.
        #expect(vm.errorMessage == "Couldn't start the game. Check your connection and try again.")
    }
}
