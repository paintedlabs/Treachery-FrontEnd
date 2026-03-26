import Testing
import Foundation
@testable import Treachery_iOS

@MainActor
struct GameBoardViewModelTests {

    // MARK: - Helpers

    private func makeSampleGame(
        state: GameState = .inProgress,
        gameMode: GameMode = .treachery,
        hostId: String = "host1",
        winningTeam: String? = nil
    ) -> Game {
        Game(
            id: "game1", code: "ABCD", hostId: hostId, state: state,
            gameMode: gameMode, maxPlayers: 8, startingLife: 40,
            winningTeam: winningTeam, playerIds: ["host1", "u1", "u2", "u3"],
            createdAt: Date()
        )
    }

    private func makeSamplePlayers() -> [Player] {
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
                   role: .assassin, identityCardId: nil, lifeTotal: 40,
                   isEliminated: false, isUnveiled: false, joinedAt: Date()),
        ]
    }

    private func makeVM(
        game: Game? = nil,
        players: [Player] = [],
        currentUserId: String? = "u1"
    ) -> GameBoardViewModel {
        let g = game ?? makeSampleGame()
        let p = players.isEmpty ? makeSamplePlayers() : players
        return GameBoardViewModel(
            gameId: g.id,
            previewPlayers: p,
            previewGame: g,
            currentUserId: currentUserId,
            firestoreManager: MockFirestoreManager(),
            cloudFunctions: MockCloudFunctions(),
            cardDatabase: CardDatabase(cards: []),
            planeDatabase: PlaneDatabase(cards: [])
        )
    }

    // MARK: - Current Player

    @Test func currentPlayerMatchesUserId() {
        let vm = makeVM(currentUserId: "u1")
        #expect(vm.currentPlayer?.userId == "u1")
        #expect(vm.currentPlayer?.displayName == "Alice")
    }

    @Test func currentPlayerNilWhenNoMatch() {
        let vm = makeVM(currentUserId: "nobody")
        #expect(vm.currentPlayer == nil)
    }

    @Test func currentPlayerNilWhenNoUserId() {
        let vm = makeVM(currentUserId: nil)
        #expect(vm.currentPlayer == nil)
    }

    // MARK: - Game State

    @Test func isGameFinished() {
        let vm = makeVM(game: makeSampleGame(state: .finished))
        #expect(vm.isGameFinished == true)
    }

    @Test func isGameNotFinished() {
        let vm = makeVM(game: makeSampleGame(state: .inProgress))
        #expect(vm.isGameFinished == false)
    }

    @Test func winningTeamParsesRole() {
        let vm = makeVM(game: makeSampleGame(winningTeam: "assassin"))
        #expect(vm.winningTeam == .assassin)
    }

    @Test func winningTeamNilWhenNoWinner() {
        let vm = makeVM(game: makeSampleGame(winningTeam: nil))
        #expect(vm.winningTeam == nil)
    }

    // MARK: - Alive Players

    @Test func alivePlayersExcludesEliminated() {
        let vm = makeVM()
        let alive = vm.alivePlayers
        #expect(alive.count == 3) // Bob is eliminated
        #expect(!alive.contains(where: { $0.displayName == "Bob" }))
    }

    // MARK: - Game Mode Booleans

    @Test func treacheryModeFlags() {
        let vm = makeVM(game: makeSampleGame(gameMode: .treachery))
        #expect(vm.isTreacheryActive == true)
        #expect(vm.isPlanechaseActive == false)
    }

    @Test func planechaseModeFlags() {
        let vm = makeVM(game: makeSampleGame(gameMode: .planechase))
        #expect(vm.isTreacheryActive == false)
        #expect(vm.isPlanechaseActive == true)
    }

    @Test func bothModeFlags() {
        let vm = makeVM(game: makeSampleGame(gameMode: .treacheryPlanechase))
        #expect(vm.isTreacheryActive == true)
        #expect(vm.isPlanechaseActive == true)
    }

    // MARK: - Host Detection

    @Test func isHostWhenMatches() {
        let vm = makeVM(game: makeSampleGame(hostId: "u1"), currentUserId: "u1")
        #expect(vm.isHost == true)
    }

    @Test func isNotHostWhenDifferent() {
        let vm = makeVM(game: makeSampleGame(hostId: "host1"), currentUserId: "u1")
        #expect(vm.isHost == false)
    }

    // MARK: - Role Visibility

    @Test func canSeeOwnRole() {
        let vm = makeVM(currentUserId: "u1")
        let alice = vm.players.first { $0.userId == "u1" }!
        #expect(vm.canSeeRole(of: alice) == true)
    }

    @Test func canSeeUnveiledPlayerRole() {
        let vm = makeVM(currentUserId: "u1")
        let bob = vm.players.first { $0.displayName == "Bob" }!
        #expect(bob.isUnveiled)
        #expect(vm.canSeeRole(of: bob) == true)
    }

    @Test func canSeeLeaderRole() {
        let vm = makeVM(currentUserId: "u1")
        let host = vm.players.first { $0.role == .leader }!
        #expect(vm.canSeeRole(of: host) == true)
    }

    @Test func cannotSeeHiddenNonLeaderRole() {
        let vm = makeVM(currentUserId: "u1")
        let carol = vm.players.first { $0.displayName == "Carol" }!
        #expect(!carol.isUnveiled)
        #expect(carol.role != .leader)
        #expect(carol.userId != "u1")
        #expect(vm.canSeeRole(of: carol) == false)
    }

    // MARK: - Die Roll Cost

    @Test func dieRollCostFirstRollFree() {
        var game = makeSampleGame(gameMode: .treacheryPlanechase)
        game.planechase = PlanechaseState(
            useOwnDeck: false, currentPlaneId: "p1", usedPlaneIds: [],
            lastDieRollerId: nil, dieRollCount: 0
        )
        let vm = makeVM(game: game)
        #expect(vm.dieRollCost == 0)
    }

    @Test func dieRollCostSecondRollFree() {
        var game = makeSampleGame(gameMode: .treacheryPlanechase)
        game.planechase = PlanechaseState(
            useOwnDeck: false, currentPlaneId: "p1", usedPlaneIds: [],
            lastDieRollerId: nil, dieRollCount: 1
        )
        let vm = makeVM(game: game)
        #expect(vm.dieRollCost == 0)
    }

    @Test func dieRollCostThirdRollCostsOne() {
        var game = makeSampleGame(gameMode: .treacheryPlanechase)
        game.planechase = PlanechaseState(
            useOwnDeck: false, currentPlaneId: "p1", usedPlaneIds: [],
            lastDieRollerId: nil, dieRollCount: 2
        )
        let vm = makeVM(game: game)
        #expect(vm.dieRollCost == 1)
    }
}
