import Testing
import Foundation
@testable import Treachery_iOS

/// What the lobby says when the server turns a request down: the server's
/// own sentence, whether it's about the lobby's state or about what was
/// asked, and a plain one when the server sent none. The errors are shaped
/// as CloudFunctions throws them, from what the Functions SDK reports.
@MainActor
struct LobbyRefusalTextTests {

    /// A waiting lobby of four, opened by its host.
    private func makeHostLobby(cloudFunctions: MockCloudFunctions) -> LobbyViewModel {
        let mockFS = MockFirestoreManager()
        mockFS.gamesToReturn["game1"] = Game(
            id: "game1", code: "ABCD", hostId: "host1", state: .waiting,
            gameMode: .treachery, maxPlayers: 8, startingLife: 40,
            winningTeam: nil, playerIds: ["host1"],
            createdAt: Date(timeIntervalSince1970: 0)
        )
        mockFS.playersToReturn = (0..<4).map { i in
            Player(
                id: "p\(i)", orderId: i, userId: "u\(i)", displayName: "Player \(i)",
                role: nil, identityCardId: nil, lifeTotal: 40,
                isEliminated: false, isUnveiled: false, joinedAt: Date(timeIntervalSince1970: 0)
            )
        }
        let vm = LobbyViewModel(gameId: "game1", isHost: true, firestoreManager: mockFS, cloudFunctions: cloudFunctions)
        vm.currentUserId = "host1"
        return vm
    }

    /// What CloudFunctions throws for a Functions SDK error with `code` and
    /// `message`: the server's sentence, or the code's name when it sent none.
    private func thrownByCloudFunctions(code: Int, message: String) -> any Error {
        let sdkError = NSError(domain: "com.firebase.functions", code: code, userInfo: [NSLocalizedDescriptionKey: message])
        return CallableRefusal(sdkError) ?? sdkError
    }

    @Test(arguments: [
        (9, "Cannot set max players below the current lobby size."),
        (3, "Invalid starting life value."),
    ])
    func aSettingTheServerRefusesShowsItsSentence(code: Int, message: String) async {
        // Failed precondition: the lobby's state. Invalid argument: what was
        // asked, such as a starting life a server older than this app
        // doesn't offer. Retrying can't help either, so neither may say to
        // check the connection.
        let functions = MockCloudFunctions()
        functions.errorToThrow = thrownByCloudFunctions(code: code, message: message)
        let vm = makeHostLobby(cloudFunctions: functions)

        await vm.updateGameSettings(startingLife: 35)

        #expect(vm.errorMessage == message)
    }

    @Test(arguments: [
        (9, "FAILED PRECONDITION"),
        (3, "INVALID ARGUMENT"),
    ])
    func aRefusalWithoutTheServersSentenceIsPlain(code: Int, placeholder: String) async {
        // Never a bare code.
        let functions = MockCloudFunctions()
        functions.errorToThrow = thrownByCloudFunctions(code: code, message: placeholder)
        let vm = makeHostLobby(cloudFunctions: functions)

        await vm.updateGameSettings(startingLife: 35)

        #expect(vm.errorMessage == "Couldn't change the game settings. Check your connection and try again.")
    }
}
