import Testing
import Foundation
@testable import Treachery_iOS

@MainActor
struct CreateGameViewModelTests {

    // MARK: - Helpers

    private func makeMockSetup() -> (MockFirestoreManager, MockCloudFunctions) {
        let mockFS = MockFirestoreManager()
        let mockCF = MockCloudFunctions()

        mockFS.usersToReturn = ["u1": TreacheryUser(
            id: "u1", displayName: "Host", email: nil, phoneNumber: nil,
            friendIds: [], createdAt: Date()
        )]

        return (mockFS, mockCF)
    }

    // MARK: - Max Traitor Rarity

    @Test func createGameSendsSelectedRarityInTreacheryMode() async {
        let (mockFS, mockCF) = makeMockSetup()
        let vm = CreateGameViewModel(firestoreManager: mockFS, cloudFunctions: mockCF)
        vm.maxTraitorRarity = .rare
        let destination = await vm.createGame(userId: "u1")
        #expect(destination == .lobby(gameId: "mock-created-game-id", isHost: true))
        #expect(mockCF.createGameCalls.count == 1)
        #expect(mockCF.createGameCalls.first?.maxTraitorRarity == "rare")
    }

    @Test func createGameDefaultsRarityToSpecial() async {
        let (mockFS, mockCF) = makeMockSetup()
        let vm = CreateGameViewModel(firestoreManager: mockFS, cloudFunctions: mockCF)
        _ = await vm.createGame(userId: "u1")
        #expect(mockCF.createGameCalls.first?.maxTraitorRarity == "special")
    }

    @Test func createGameOmitsRarityWithoutTreachery() async {
        let (mockFS, mockCF) = makeMockSetup()
        let vm = CreateGameViewModel(firestoreManager: mockFS, cloudFunctions: mockCF)
        vm.gameMode = .planechase
        vm.maxTraitorRarity = .rare
        _ = await vm.createGame(userId: "u1")
        #expect(mockCF.createGameCalls.count == 1)
        #expect(mockCF.createGameCalls.first?.maxTraitorRarity == nil)
    }

    @Test func createGameSetsErrorOnFailure() async {
        let (mockFS, mockCF) = makeMockSetup()
        mockCF.errorToThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "create failed"])
        let vm = CreateGameViewModel(firestoreManager: mockFS, cloudFunctions: mockCF)
        let destination = await vm.createGame(userId: "u1")
        #expect(destination == nil)
        #expect(vm.errorMessage == "create failed")
    }
}
