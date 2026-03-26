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

    // MARK: - leaveGame

    @Test func leaveGameCallsCloudFunction() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: false,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await vm.leaveGame(userId: "u0")
        #expect(mockCF.leaveGameCalls == ["game1"])
    }

    @Test func leaveGameSetsErrorOnFailure() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        mockCF.errorToThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "leave failed"])
        let vm = LobbyViewModel(
            gameId: "game1", isHost: false,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        await vm.leaveGame(userId: "u0")
        #expect(vm.errorMessage == "leave failed")
    }

    @Test func leaveGameClearsErrorBeforeCall() async {
        let (mockFS, mockCF) = makeMockSetup(players: makePlayers(count: 4))
        let vm = LobbyViewModel(
            gameId: "game1", isHost: false,
            firestoreManager: mockFS, cloudFunctions: mockCF
        )
        vm.errorMessage = "old error"
        await vm.leaveGame(userId: "u0")
        // errorMessage should be nil (cleared before call, no new error)
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
