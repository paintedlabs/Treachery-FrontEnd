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
        #expect(vm.errorMessage == "boom")
    }
}
