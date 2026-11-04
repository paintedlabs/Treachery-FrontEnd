import Testing
import Foundation
@testable import Treachery_iOS

/// joinGame's payload parsing. Opening a lobby with an empty game id hands
/// Firestore an empty document path, which crashes, so a response without a
/// usable id has to throw instead.
struct JoinGameResultTests {

    @Test func readsGameIdAndAction() throws {
        let result = try JoinGameResult(payload: ["action": "already_joined", "gameId": "g42"])
        #expect(result.gameId == "g42")
        #expect(result.action == "already_joined")
    }

    @Test func defaultsActionToJoined() throws {
        let result = try JoinGameResult(payload: ["gameId": "g42"])
        #expect(result.action == "joined")
    }

    @Test func missingGameIdThrows() {
        #expect(throws: JoinGameResult.MissingGameIdError.self) {
            _ = try JoinGameResult(payload: ["action": "joined"])
        }
    }

    @Test func emptyGameIdThrows() {
        #expect(throws: JoinGameResult.MissingGameIdError.self) {
            _ = try JoinGameResult(payload: ["action": "joined", "gameId": ""])
        }
    }

    @Test func nonStringGameIdThrows() {
        #expect(throws: JoinGameResult.MissingGameIdError.self) {
            _ = try JoinGameResult(payload: ["gameId": 42])
        }
    }

    @Test func nonDictionaryPayloadThrows() {
        #expect(throws: JoinGameResult.MissingGameIdError.self) {
            _ = try JoinGameResult(payload: "g42")
        }
        #expect(throws: JoinGameResult.MissingGameIdError.self) {
            _ = try JoinGameResult(payload: nil)
        }
    }
}

@MainActor
struct JoinGameViewModelTests {

    @Test func responseWithoutGameIdDoesNotOpenALobby() async {
        let mockCF = MockCloudFunctions()
        mockCF.joinGamePayload = ["action": "joined"]
        let vm = JoinGameViewModel(cloudFunctions: mockCF)
        vm.gameCode = "ABCD"

        let destination = await vm.joinGame()

        #expect(destination == nil)
        #expect(vm.errorMessage == "Couldn't join the game. Please try again.")
        #expect(!vm.isJoining)
    }

    @Test func refusedJoinShowsTheServersReason() async {
        // lobby.js writes these for players: a wrong code, a full game, a
        // game that has started.
        let mockCF = MockCloudFunctions()
        mockCF.errorToThrow = CallableRefusal(reason: .failedPrecondition, message: "This game is full.")
        let vm = JoinGameViewModel(cloudFunctions: mockCF)
        vm.gameCode = "ABCD"

        let destination = await vm.joinGame()

        #expect(destination == nil)
        #expect(vm.errorMessage == "This game is full.")
    }

    @Test func otherJoinFailuresNeverShowTheSDKsDescription() async {
        let mockCF = MockCloudFunctions()
        mockCF.errorToThrow = NSError(
            domain: "com.firebase.functions", code: 13,
            userInfo: [NSLocalizedDescriptionKey: "INTERNAL"]
        )
        let vm = JoinGameViewModel(cloudFunctions: mockCF)
        vm.gameCode = "ABCD"

        _ = await vm.joinGame()

        #expect(vm.errorMessage == "Couldn't join the game. Check your connection and try again.")
        #expect(!vm.isJoining)
    }

    @Test func responseWithGameIdOpensThatLobby() async {
        let mockCF = MockCloudFunctions()
        mockCF.joinGamePayload = ["action": "joined", "gameId": "g42"]
        let vm = JoinGameViewModel(cloudFunctions: mockCF)
        vm.gameCode = "ABCD"

        let destination = await vm.joinGame()

        #expect(destination == .lobby(gameId: "g42", isHost: false))
        #expect(mockCF.joinGameCalls == ["ABCD"])
    }
}
