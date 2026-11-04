import Testing
import Foundation
@testable import Treachery_iOS

/// What the board says when one of its actions fails: the server's own
/// reason when it turned the request down because of the game's state or
/// what was asked, otherwise a plain sentence saying what to try. Never the
/// SDK's text.
@MainActor
struct GameBoardErrorTextTests {

    /// What the Functions SDK throws when the request never got an answer.
    private let unreachable = NSError(
        domain: "com.firebase.functions", code: 14, userInfo: [NSLocalizedDescriptionKey: "UNAVAILABLE"]
    )

    private func makeVM(
        cloudFunctions: MockCloudFunctions = MockCloudFunctions(),
        firestoreManager: MockFirestoreManager = MockFirestoreManager()
    ) -> GameBoardViewModel {
        let players = (0..<4).map { i in
            Player(
                id: "p\(i)", orderId: i, userId: "u\(i)", displayName: "Player \(i)",
                role: i == 0 ? .leader : .traitor, identityCardId: "card\(i)", lifeTotal: 40,
                isEliminated: false, isUnveiled: false, joinedAt: Date(timeIntervalSince1970: 0)
            )
        }
        let game = Game(
            id: "game1", code: "ABCD", hostId: "u1", state: .inProgress,
            gameMode: .treacheryPlanechase, maxPlayers: 8, startingLife: 40,
            winningTeam: nil, playerIds: players.map(\.userId),
            createdAt: Date(timeIntervalSince1970: 0)
        )
        return GameBoardViewModel(
            gameId: game.id,
            previewPlayers: players,
            previewGame: game,
            currentUserId: "u1",
            firestoreManager: firestoreManager,
            cloudFunctions: cloudFunctions,
            cardDatabase: CardDatabase(cards: []),
            planeDatabase: PlaneDatabase(cards: []),
            clock: TestClock()
        )
    }

    // MARK: - The server's reason

    @Test func aRefusedDieRollGivesTheServersReason() async {
        let functions = MockCloudFunctions()
        functions.errorToThrow = CallableRefusal(
            reason: .failedPrecondition, message: "Eliminated players cannot take Planechase actions."
        )
        let vm = makeVM(cloudFunctions: functions)

        await vm.rollDie()

        #expect(vm.errorMessage == "Eliminated players cannot take Planechase actions.")
    }

    @Test func aRefusedForfeitGivesTheServersReason() async {
        let functions = MockCloudFunctions()
        functions.errorToThrow = CallableRefusal(reason: .failedPrecondition, message: "You are already eliminated.")
        let vm = makeVM(cloudFunctions: functions)

        await vm.eliminateAndLeave()

        #expect(vm.errorMessage == "You are already eliminated.")
    }

    @Test func aRefusedUnveilGivesTheServersReason() async {
        let functions = MockCloudFunctions()
        functions.errorToThrow = CallableRefusal(reason: .failedPrecondition, message: "Game is not in progress.")
        let vm = makeVM(cloudFunctions: functions)

        await vm.unveilCurrentPlayer()?.value

        #expect(vm.unveilFailure == "Game is not in progress.")
    }

    @Test func aRefusedAbilityGivesTheServersReason() async {
        let functions = MockCloudFunctions()
        functions.errorToThrow = CallableRefusal(
            reason: .failedPrecondition, message: "This ability has already been resolved."
        )
        let vm = makeVM(cloudFunctions: functions)

        await vm.resolveMetamorph(targetPlayerId: "p2")

        #expect(vm.errorMessage == "This ability has already been resolved.")
    }

    @Test func aRequestTheServerRefusesGivesItsSentence() async {
        // Invalid argument: what was asked, not the game's state.
        let functions = MockCloudFunctions()
        let sdkError = NSError(
            domain: "com.firebase.functions", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Winners must be players in this game."]
        )
        functions.errorToThrow = CallableRefusal(sdkError) ?? sdkError
        let vm = makeVM(cloudFunctions: functions)

        await vm.endGame(winnerUserIds: ["u9"])

        #expect(vm.errorMessage == "Winners must be players in this game.")
    }

    @Test func aMissingGamesReasonIsNotShown() async {
        // A missing game gets the plain sentence: the board's listener says
        // the game is gone, and "Game not found." adds nothing.
        let functions = MockCloudFunctions()
        functions.errorToThrow = CallableRefusal(reason: .notFound, message: "Game not found.")
        let vm = makeVM(cloudFunctions: functions)

        await vm.endGame()

        #expect(vm.errorMessage == "Couldn't end the game. Check your connection and try again.")
    }

    // MARK: - Plain sentences

    @Test func aFailedPlaneChoiceNamesThePlane() async {
        let functions = MockCloudFunctions()
        let vm = makeVM(cloudFunctions: functions)
        functions.errorToThrow = unreachable
        let naya = PlaneCard(id: "plane1", name: "Naya", typeLine: "Plane", oracleText: "Big.", imageUri: nil, isPhenomenon: false)

        await vm.selectTunnelPlane(naya)

        #expect(vm.errorMessage == "Couldn't planeswalk to Naya. Check your connection and try again.")
    }

    @Test func aFailedColorChangeIsPlain() async {
        let firestore = MockFirestoreManager()
        firestore.errorToThrow = NSError(
            domain: "FIRFirestoreErrorDomain", code: 14, userInfo: [NSLocalizedDescriptionKey: "The service is currently unavailable."]
        )
        let vm = makeVM(firestoreManager: firestore)

        await vm.updatePlayerColor("#e74c3c")

        #expect(vm.errorMessage == "Couldn't change your color. Check your connection and try again.")
    }

    /// A spectator's only action is changing color, so a later attempt must
    /// clear the last failure, as every other action does.
    @Test func aLaterColorChangeClearsTheLastFailure() async {
        let firestore = MockFirestoreManager()
        firestore.errorToThrow = NSError(domain: "FIRFirestoreErrorDomain", code: 14)
        let vm = makeVM(firestoreManager: firestore)
        await vm.updatePlayerColor("#e74c3c")
        #expect(vm.errorMessage != nil)

        firestore.errorToThrow = nil
        await vm.updatePlayerColor("#3498db")

        #expect(vm.errorMessage == nil)
    }

    @Test func failedAbilitiesArePlain() async {
        let functions = MockCloudFunctions()
        functions.errorToThrow = unreachable
        let vm = makeVM(cloudFunctions: functions)

        await vm.resolveMetamorph(targetPlayerId: "p2")
        #expect(vm.errorMessage == "Couldn't steal that identity. Check your connection and try again.")

        await vm.resolvePuppetMaster(redistributions: ["p2": "card3", "p3": "card2"])
        #expect(vm.errorMessage == "Couldn't redistribute the cards. Check your connection and try again.")

        await vm.resolveWearerOfMasks(chosenCardId: "guardian_01")
        #expect(vm.errorMessage == "Couldn't become that identity. Check your connection and try again.")

        await vm.resolveWearerOfMasks(chosenCardId: nil)
        #expect(vm.errorMessage == "Couldn't decline the ability. Check your connection and try again.")
    }
}
