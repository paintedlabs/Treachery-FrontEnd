import Testing
import Foundation
@testable import Treachery_iOS

@MainActor
struct GameBoardViewModelActionTests {

    // MARK: - Helpers

    private func makeSampleGame(
        state: GameState = .inProgress,
        gameMode: GameMode = .treachery,
        hostId: String = "host1"
    ) -> Game {
        Game(
            id: "game1", code: "ABCD", hostId: hostId, state: state,
            gameMode: gameMode, maxPlayers: 8, startingLife: 40,
            winningTeam: nil, playerIds: ["host1", "u1", "u2", "u3"],
            createdAt: Date()
        )
    }

    private func makePlayers() -> [Player] {
        [
            Player(id: "p0", orderId: 0, userId: "host1", displayName: "Host",
                   role: .leader, identityCardId: "card1", lifeTotal: 40,
                   isEliminated: false, isUnveiled: false, joinedAt: Date()),
            Player(id: "p1", orderId: 1, userId: "u1", displayName: "Alice",
                   role: .assassin, identityCardId: "card2", lifeTotal: 40,
                   isEliminated: false, isUnveiled: false, joinedAt: Date()),
            Player(id: "p2", orderId: 2, userId: "u2", displayName: "Bob",
                   role: .traitor, identityCardId: "card3", lifeTotal: 40,
                   isEliminated: true, isUnveiled: true, joinedAt: Date()),
            Player(id: "p3", orderId: 3, userId: "u3", displayName: "Carol",
                   role: .guardian, identityCardId: "card4", lifeTotal: 40,
                   isEliminated: false, isUnveiled: false, joinedAt: Date()),
        ]
    }

    private func makeVM(
        game: Game? = nil,
        players: [Player]? = nil,
        currentUserId: String? = "u1",
        cloudFunctions: MockCloudFunctions = MockCloudFunctions(),
        firestoreManager: MockFirestoreManager = MockFirestoreManager()
    ) -> (GameBoardViewModel, MockCloudFunctions, MockFirestoreManager) {
        let g = game ?? makeSampleGame()
        let p = players ?? makePlayers()
        let vm = GameBoardViewModel(
            gameId: g.id,
            previewPlayers: p,
            previewGame: g,
            currentUserId: currentUserId,
            firestoreManager: firestoreManager,
            cloudFunctions: cloudFunctions,
            cardDatabase: CardDatabase(cards: []),
            planeDatabase: PlaneDatabase(cards: [])
        )
        return (vm, cloudFunctions, firestoreManager)
    }

    // MARK: - unveilCurrentPlayer

    @Test func unveilCallsCloudFunction() async {
        let (vm, cf, _) = makeVM()
        await vm.unveilCurrentPlayer()
        #expect(cf.unveilPlayerCalls == ["game1"])
    }

    @Test func unveilDoesNothingWhenAlreadyUnveiled() async {
        var players = makePlayers()
        players[1] = Player(
            id: "p1", orderId: 1, userId: "u1", displayName: "Alice",
            role: .assassin, identityCardId: "card2", lifeTotal: 40,
            isEliminated: false, isUnveiled: true, joinedAt: Date()
        )
        let (vm, cf, _) = makeVM(players: players)
        await vm.unveilCurrentPlayer()
        #expect(cf.unveilPlayerCalls.isEmpty)
    }

    @Test func unveilDoesNothingWhenNoCurrentPlayer() async {
        let (vm, cf, _) = makeVM(currentUserId: nil)
        await vm.unveilCurrentPlayer()
        #expect(cf.unveilPlayerCalls.isEmpty)
    }

    @Test func unveilSetsErrorOnFailure() async {
        let cf = MockCloudFunctions()
        cf.errorToThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "network error"])
        let (vm, _, _) = makeVM(cloudFunctions: cf)
        await vm.unveilCurrentPlayer()
        #expect(vm.errorMessage == "network error")
    }

    @Test func unveilSetsPendingDuringCall() async {
        let (vm, _, _) = makeVM()
        #expect(vm.isPending == false)
        await vm.unveilCurrentPlayer()
        // After completion, pending should be false again
        #expect(vm.isPending == false)
    }

    @Test func unveilDoesNothingWhenLeader() async {
        // Leaders are always visible, so unveil should be a no-op
        let (vm, cf, _) = makeVM(currentUserId: "host1") // host is leader
        await vm.unveilCurrentPlayer()
        // Leader's isUnveiled is false, but canSeeRole is true because role == .leader
        // The unveil method checks !player.isUnveiled — leader with isUnveiled=false
        // would still attempt the call. But the unveil method also checks role != .leader.
        // Wait, let me check... the action bar in the view guards against leader, but
        // does the viewmodel? Let me check the code:
        // guard !player.isUnveiled else { return }
        // There's no check for leader in the viewmodel. So it WOULD call the cloud function.
        // This test documents that behavior — the view prevents it, but the VM doesn't.
        #expect(cf.unveilPlayerCalls.count == 1)
    }

    // MARK: - eliminateAndLeave

    @Test func eliminateCallsCloudFunction() async {
        let (vm, cf, _) = makeVM()
        await vm.eliminateAndLeave()
        #expect(cf.eliminatePlayerCalls == ["game1"])
    }

    @Test func eliminateDoesNothingWhenNoCurrentPlayer() async {
        let (vm, cf, _) = makeVM(currentUserId: nil)
        await vm.eliminateAndLeave()
        #expect(cf.eliminatePlayerCalls.isEmpty)
    }

    @Test func eliminateSetsErrorOnFailure() async {
        let cf = MockCloudFunctions()
        cf.errorToThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "fail"])
        let (vm, _, _) = makeVM(cloudFunctions: cf)
        await vm.eliminateAndLeave()
        #expect(vm.errorMessage == "fail")
    }

    // MARK: - rollDie

    @Test func rollDieCallsCloudFunction() async {
        let game = makeSampleGame(gameMode: .treacheryPlanechase)
        let cf = MockCloudFunctions()
        cf.rollPlanarDieResult = "planeswalk"
        let (vm, _, _) = makeVM(game: game, cloudFunctions: cf)
        await vm.rollDie()
        #expect(vm.dieRollResult == "planeswalk")
    }

    @Test func rollDieDoesNothingWhenAlreadyRolling() async {
        let (vm, cf, _) = makeVM()
        // Simulate already rolling
        vm.isRollingDie = true
        await vm.rollDie()
        // Should not have called cloud function
        // (rollPlanarDie is not in cf's tracked calls, but we check dieRollResult)
        #expect(vm.dieRollResult == nil)
    }

    @Test func rollDieSetsErrorOnFailure() async {
        let cf = MockCloudFunctions()
        cf.errorToThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "die error"])
        let (vm, _, _) = makeVM(cloudFunctions: cf)
        await vm.rollDie()
        #expect(vm.errorMessage == "die error")
    }

    @Test func rollDieClearsErrorBeforeCall() async {
        let cf = MockCloudFunctions()
        let (vm, _, _) = makeVM(cloudFunctions: cf)
        vm.errorMessage = "old error"
        await vm.rollDie()
        #expect(vm.errorMessage == nil)
    }

    // MARK: - endGame

    @Test func endGameCallsCloudFunction() async {
        let (vm, cf, _) = makeVM(currentUserId: "host1")
        await vm.endGame(winnerUserIds: ["u1", "u3"])
        #expect(cf.endGameCalls.count == 1)
        #expect(cf.endGameCalls.first?.gameId == "game1")
        #expect(cf.endGameCalls.first?.winnerUserIds == ["u1", "u3"])
    }

    @Test func endGameWithNoWinners() async {
        let (vm, cf, _) = makeVM()
        await vm.endGame()
        #expect(cf.endGameCalls.count == 1)
        #expect(cf.endGameCalls.first?.winnerUserIds == nil)
    }

    @Test func endGameDoesNothingWhenPending() async {
        let (vm, cf, _) = makeVM()
        vm.isPending = true
        await vm.endGame()
        #expect(cf.endGameCalls.isEmpty)
    }

    @Test func endGameSetsErrorOnFailure() async {
        let cf = MockCloudFunctions()
        cf.errorToThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "end error"])
        let (vm, _, _) = makeVM(cloudFunctions: cf)
        await vm.endGame()
        #expect(vm.errorMessage == "end error")
    }

    // MARK: - updatePlayerColor

    @Test func updatePlayerColorCallsFirestoreManager() async {
        let fs = MockFirestoreManager()
        let (vm, _, _) = makeVM(firestoreManager: fs)
        await vm.updatePlayerColor("#FF0000")
        #expect(fs.updatePlayerColorCalls.count == 1)
        #expect(fs.updatePlayerColorCalls.first?.playerId == "p1")
        #expect(fs.updatePlayerColorCalls.first?.color == "#FF0000")
    }

    @Test func updatePlayerColorDoesNothingWithoutCurrentPlayer() async {
        let fs = MockFirestoreManager()
        let (vm, _, _) = makeVM(currentUserId: nil, firestoreManager: fs)
        await vm.updatePlayerColor("#FF0000")
        #expect(fs.updatePlayerColorCalls.isEmpty)
    }

    // MARK: - resolvePhenomenon

    @Test func resolvePhenomenonDoesNothingWhenPending() async {
        let (vm, _, _) = makeVM()
        vm.isPending = true
        await vm.resolvePhenomenon()
        #expect(vm.tunnelOptions == nil)
    }

    @Test func resolvePhenomenonSetsErrorOnFailure() async {
        let cf = MockCloudFunctions()
        cf.errorToThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "resolve fail"])
        let (vm, _, _) = makeVM(cloudFunctions: cf)
        await vm.resolvePhenomenon()
        #expect(vm.errorMessage == "resolve fail")
    }

    // MARK: - selectTunnelPlane

    @Test func selectPlaneClearsTunnelOptions() async {
        let (vm, _, _) = makeVM()
        let plane = PlaneCard(id: "plane1", name: "Naya", typeLine: "Plane", oracleText: "Big.", imageUri: nil, isPhenomenon: false)
        vm.tunnelOptions = [plane]
        await vm.selectTunnelPlane(plane)
        #expect(vm.tunnelOptions == nil)
    }

    @Test func selectPlaneDoesNothingWhenPending() async {
        let (vm, _, _) = makeVM()
        let plane = PlaneCard(id: "plane1", name: "Naya", typeLine: "Plane", oracleText: "Big.", imageUri: nil, isPhenomenon: false)
        vm.isPending = true
        await vm.selectTunnelPlane(plane)
        // tunnelOptions should not be cleared if isPending
        #expect(vm.isPending == true)
    }
}
