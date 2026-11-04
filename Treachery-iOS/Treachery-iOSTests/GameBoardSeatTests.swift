import Testing
import Foundation
@testable import Treachery_iOS

/// What the signed-in user can do on the board, by seat and game mode. The
/// server eliminates players in every mode, so none of this may depend on
/// Treachery being in play.
@MainActor
struct GameBoardSeatTests {

    // MARK: - Helpers

    /// u0 hosts unless `hostId` says otherwise. u1 is the signed-in user
    /// unless `currentUserId` says otherwise, eliminated when
    /// `currentUserEliminated`. u2 went out earlier, and like every
    /// eliminated player the server has marked them unveiled.
    private func makeVM(
        gameMode: GameMode,
        hostId: String = "u0",
        currentUserId: String? = "u1",
        currentUserEliminated: Bool = false,
        cloudFunctions: MockCloudFunctions = MockCloudFunctions()
    ) -> GameBoardViewModel {
        let dealsRoles = gameMode.includesTreachery
        let players = (0..<4).map { i in
            let isEliminated = i == 2 || (i == 1 && currentUserEliminated)
            return Player(
                id: "p\(i)", orderId: i, userId: "u\(i)", displayName: "Player \(i)",
                role: dealsRoles ? (i == 0 ? .leader : .guardian) : nil,
                identityCardId: dealsRoles ? "card\(i)" : nil,
                lifeTotal: isEliminated ? 0 : 40,
                isEliminated: isEliminated, isUnveiled: isEliminated, joinedAt: Date()
            )
        }
        let game = Game(
            id: "game1", code: "ABCD", hostId: hostId, state: .inProgress,
            gameMode: gameMode, maxPlayers: 8, startingLife: 40,
            winningTeam: nil, playerIds: players.map(\.userId),
            createdAt: Date()
        )
        return GameBoardViewModel(
            gameId: game.id,
            previewPlayers: players,
            previewGame: game,
            currentUserId: currentUserId,
            firestoreManager: MockFirestoreManager(),
            cloudFunctions: cloudFunctions,
            cardDatabase: CardDatabase(cards: []),
            planeDatabase: PlaneDatabase(cards: []),
            clock: TestClock()
        )
    }

    // MARK: - Seat

    @Test(arguments: GameMode.allCases)
    func eliminatedPlayerSpectatesInEveryMode(_ mode: GameMode) {
        let vm = makeVM(gameMode: mode, currentUserEliminated: true)
        #expect(vm.seat == .spectating)
        // The spectator bar, and with it a way home.
        #expect(vm.spectatorLeave == .goHome)
        #expect(!vm.canAdjustLife)
        #expect(!vm.canRollDie)
    }

    @Test(arguments: GameMode.allCases)
    func livingPlayerPlaysWithoutTheSpectatorBar(_ mode: GameMode) {
        let vm = makeVM(gameMode: mode)
        #expect(vm.seat == .playing)
        #expect(vm.spectatorLeave == nil)
        #expect(vm.canAdjustLife)
        #expect(vm.canRollDie)
    }

    @Test func userMissingFromThePlayersIsUnseated() {
        let vm = makeVM(gameMode: .planechase, currentUserId: "u9")
        #expect(vm.seat == .unseated)
        #expect(vm.spectatorLeave == nil)
        #expect(!vm.canAdjustLife)
        #expect(!vm.canRollDie)
    }

    // MARK: - Leaving and ending

    @Test(arguments: [GameMode.planechase, GameMode.none])
    func eliminatedGuestCanLeaveAGameOnlyTheHostCanEnd(_ mode: GameMode) {
        // Nothing used to lead them off the board in these modes: the
        // spectator bar was Treachery's alone, and the game runs until the
        // host ends it.
        let vm = makeVM(gameMode: mode, currentUserEliminated: true)
        #expect(vm.spectatorLeave == .goHome)
        #expect(!vm.canEndGame)
    }

    @Test(arguments: [GameMode.planechase, GameMode.none])
    func eliminatedHostKeepsEndGameAndConfirmsLeaving(_ mode: GameMode) {
        let vm = makeVM(gameMode: mode, hostId: "u1", currentUserEliminated: true)
        #expect(vm.canEndGame)
        #expect(vm.spectatorLeave == .confirmFirst)
    }

    @Test(arguments: [GameMode.treachery, GameMode.treacheryPlanechase])
    func treacheryGamesEndWithoutTheHost(_ mode: GameMode) {
        // Their win conditions end them, so the host has no End Game, and
        // leaving strands nobody.
        let vm = makeVM(gameMode: mode, hostId: "u1", currentUserEliminated: true)
        #expect(!vm.canEndGame)
        #expect(vm.spectatorLeave == .goHome)
    }

    // MARK: - Spectator guards

    @Test func spectatorCantChangeLife() {
        let vm = makeVM(gameMode: .none, currentUserEliminated: true)
        vm.adjustLife(for: "p0", by: -1)
        #expect(vm.players.first { $0.id == "p0" }?.lifeTotal == 40)
        #expect(vm.lifeChangeDebounces.isEmpty)
    }

    @Test func spectatorCantRollThePlanarDie() async {
        let functions = MockCloudFunctions()
        let vm = makeVM(gameMode: .planechase, currentUserEliminated: true, cloudFunctions: functions)
        await vm.rollDie()
        #expect(functions.rollPlanarDieCalls.isEmpty)
        #expect(vm.dieRollResult == nil)
        // A tap the server would refuse isn't sent, so there's no error either.
        #expect(vm.errorMessage == nil)
    }

    @Test func playerStillInTheGameRollsThePlanarDie() async {
        let functions = MockCloudFunctions()
        let vm = makeVM(gameMode: .planechase, cloudFunctions: functions)
        await vm.rollDie()
        #expect(functions.rollPlanarDieCalls == ["game1"])
    }

    @Test(arguments: GameMode.allCases)
    func unveilIsOfferedOnlyToTreacheryPlayersStillInTheGame(_ mode: GameMode) {
        #expect(makeVM(gameMode: mode).offersUnveil == mode.includesTreachery)
        #expect(!makeVM(gameMode: mode, currentUserEliminated: true).offersUnveil)
    }

    // MARK: - Role labels

    @Test(arguments: [GameMode.planechase, GameMode.none])
    func gamesWithoutTreacheryShowNoRoles(_ mode: GameMode) throws {
        let vm = makeVM(gameMode: mode)
        let me = try #require(vm.currentPlayer)
        let eliminated = try #require(vm.players.first { $0.id == "p2" })
        #expect(!vm.canSeeRole(of: me))
        #expect(!vm.canSeeRole(of: eliminated))
    }

    @Test(arguments: [GameMode.treachery, GameMode.treacheryPlanechase])
    func treacheryShowsYourRoleAndUnveiledOnes(_ mode: GameMode) throws {
        let vm = makeVM(gameMode: mode)
        let me = try #require(vm.currentPlayer)
        let eliminated = try #require(vm.players.first { $0.id == "p2" })
        #expect(vm.canSeeRole(of: me))
        #expect(vm.canSeeRole(of: eliminated))
    }
}
