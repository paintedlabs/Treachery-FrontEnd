import Testing
import Foundation
@testable import Treachery_iOS

/// Saving the commander name. The lobby saves it by itself, whenever typing
/// pauses and when the lobby leaves the screen, so a save must send only
/// what the player typed and leave everything else alone.
@MainActor
struct LobbyCommanderNameTests {

    // MARK: - Helpers

    /// Opens a waiting lobby as u1, whose commander name field fills with
    /// `commanderName` from the first snapshot.
    private func makeLobby(
        commanderName: String? = "Krenko, Mob Boss",
        cloudFunctions: MockCloudFunctions = MockCloudFunctions()
    ) -> (LobbyViewModel, MockFirestoreManager) {
        let mockFS = MockFirestoreManager()
        mockFS.gamesToReturn["game1"] = Game(
            id: "game1", code: "ABCD", hostId: "u0", state: .waiting,
            gameMode: .treachery, maxPlayers: 8, startingLife: 40,
            winningTeam: nil, playerIds: ["u0", "u1"],
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
        mockFS.playersToReturn = players(commanderName: commanderName)
        let vm = LobbyViewModel(
            gameId: "game1", isHost: false,
            firestoreManager: mockFS, cloudFunctions: cloudFunctions
        )
        vm.currentUserId = "u1"
        return (vm, mockFS)
    }

    /// u0 and u1, both with `commanderName`.
    private func players(commanderName: String?) -> [Player] {
        (0..<2).map { i in
            Player(
                id: "p\(i)", orderId: i, userId: "u\(i)", displayName: "Player \(i)",
                role: nil, identityCardId: nil, lifeTotal: 40,
                isEliminated: false, isUnveiled: false, joinedAt: Date(timeIntervalSince1970: 0),
                commanderName: commanderName
            )
        }
    }

    // MARK: - Failures

    @Test func saveLeavesAFailedLeavesErrorAlone() async {
        // The autosave runs whenever typing pauses, which can be just after a
        // leave failed. Clearing that failure took its message and its Back
        // to Home away without the player doing anything.
        let functions = MockCloudFunctions()
        functions.errorToThrow = URLError(.notConnectedToInternet)
        let (vm, mockFS) = makeLobby(commanderName: nil, cloudFunctions: functions)
        _ = await vm.leave()

        vm.commanderNameDraft = "Atraxa"
        await vm.saveCommanderName()

        #expect(mockFS.updateCommanderNameCalls.map(\.name) == ["Atraxa"])
        #expect(vm.requestFailure == .leave("Couldn't leave the lobby. Check your connection and try again."))
        #expect(vm.offersHomeWithoutLeaving)
    }

    @Test func failedSaveShowsUntilTheNextSave() async {
        let (vm, mockFS) = makeLobby(commanderName: nil)
        mockFS.errorToThrow = NSError(domain: "test", code: 1)

        vm.commanderNameDraft = "Atraxa"
        await vm.saveCommanderName()
        #expect(vm.errorMessage == "Couldn't save your commander name. Check your connection and try again.")
        #expect(vm.requestFailure == nil)

        mockFS.errorToThrow = nil
        vm.commanderNameDraft = "Atraxa, Praetors' Voice"
        await vm.saveCommanderName()
        #expect(vm.errorMessage == nil)
    }

}
