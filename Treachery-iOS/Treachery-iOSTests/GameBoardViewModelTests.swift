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
    //
    // rollPlanarDie (planechase.js) charges whoever rolled last as many mana
    // as they've rolled so far, and anyone else nothing.

    private func makePlanechaseVM(
        lastDieRollerId: String?,
        dieRollCount: Int,
        currentUserId: String? = "u1"
    ) -> GameBoardViewModel {
        var game = makeSampleGame(gameMode: .treacheryPlanechase)
        game.planechase = PlanechaseState(
            useOwnDeck: false, currentPlaneId: "p1", usedPlaneIds: [],
            lastDieRollerId: lastDieRollerId, dieRollCount: dieRollCount
        )
        return makeVM(game: game, currentUserId: currentUserId)
    }

    @Test func firstRollIsFree() {
        let vm = makePlanechaseVM(lastDieRollerId: nil, dieRollCount: 0)
        #expect(vm.dieRollCost == 0)
    }

    @Test(arguments: [1, 2, 3])
    func rollingAgainCostsTheRollsSoFar(rollsSoFar: Int) {
        // After one roll the next costs 1 mana; this used to show 0.
        let vm = makePlanechaseVM(lastDieRollerId: "u1", dieRollCount: rollsSoFar)
        #expect(vm.dieRollCost == rollsSoFar)
    }

    @Test func someoneElsesRollLeavesYoursFree() {
        // This used to show their cost, 2, to everyone.
        let vm = makePlanechaseVM(lastDieRollerId: "u2", dieRollCount: 3)
        #expect(vm.dieRollCost == 0)
    }

    @Test func noSignedInUserIsNotTheLastRoller() {
        // nil == nil must not make a missing user the roller.
        let vm = makePlanechaseVM(lastDieRollerId: nil, dieRollCount: 2, currentUserId: nil)
        #expect(vm.dieRollCost == 0)
    }

    // MARK: - Traitor Ability Retry

    private func abilityPlayer(
        cardId: String = "traitor_07",
        originalCardId: String? = nil,
        isUnveiled: Bool = true,
        isEliminated: Bool = false,
        abilityResolved: Bool = false
    ) -> Player {
        Player(
            id: "p1", orderId: 1, userId: "u1", displayName: "Alice",
            role: .traitor, identityCardId: cardId, lifeTotal: 40,
            isEliminated: isEliminated, isUnveiled: isUnveiled, joinedAt: Date(),
            originalIdentityCardId: originalCardId,
            abilityResolved: abilityResolved
        )
    }

    @Test func resolvableAbilityWhenUnveiledMetamorph() {
        let vm = makeVM(players: [abilityPlayer()])
        #expect(vm.resolvableAbility == .metamorph)
    }

    @Test func resolvableAbilityWhenUnveiledPuppetMaster() {
        let vm = makeVM(players: [abilityPlayer(cardId: "traitor_09")])
        #expect(vm.resolvableAbility == .puppetMaster)
    }

    @Test func resolvableAbilityNilOnceResolved() {
        let vm = makeVM(players: [abilityPlayer(abilityResolved: true)])
        #expect(vm.resolvableAbility == nil)
    }

    @Test func resolvableAbilityNilWhenStillVeiled() {
        let vm = makeVM(players: [abilityPlayer(isUnveiled: false)])
        #expect(vm.resolvableAbility == nil)
    }

    @Test func resolvableAbilityNilWhenEliminated() {
        let vm = makeVM(players: [abilityPlayer(isEliminated: true)])
        #expect(vm.resolvableAbility == nil)
    }

    @Test func resolvableAbilityNilForNonAbilityCard() {
        let vm = makeVM(players: [abilityPlayer(cardId: "assassin_01")])
        #expect(vm.resolvableAbility == nil)
    }

    @Test(arguments: ["traitor_07", "traitor_09", "traitor_13"])
    func abilityCardSwappedInGivesNoAbility(cardId: String) {
        // A Puppet Master handed it over; every resolver refuses a holder
        // who was dealt another card ("Your card is not The Metamorph.").
        let vm = makeVM(players: [abilityPlayer(cardId: cardId, originalCardId: "guardian_03")])
        #expect(vm.resolvableAbility == nil)
        vm.presentAbilityResolver()
        #expect(vm.pendingAbilityResolution == nil)
    }

    @Test func abilityCardDealtAndHeldAgainKeepsItsAbility() {
        // The server records the card first dealt; holding that one again
        // passes its check.
        let vm = makeVM(players: [abilityPlayer(cardId: "traitor_07", originalCardId: "traitor_07")])
        #expect(vm.resolvableAbility == .metamorph)
    }

    @Test func presentAbilityResolverOpensSheet() {
        let vm = makeVM(players: [abilityPlayer()])
        vm.presentAbilityResolver()
        #expect(vm.pendingAbilityResolution?.abilityType == .metamorph)
    }

    @Test func presentAbilityResolverDoesNothingWhenResolved() {
        let vm = makeVM(players: [abilityPlayer(abilityResolved: true)])
        vm.presentAbilityResolver()
        #expect(vm.pendingAbilityResolution == nil)
    }

    @Test func metamorphIsNotOfferedACardAlreadyTaken() {
        // A Metamorph leaves its victim without a card, and resolveMetamorph
        // refuses such a target: "Target has no identity to steal."
        let players = [
            abilityPlayer(),
            Player(id: "p2", orderId: 2, userId: "u2", displayName: "Bob",
                   role: .assassin, identityCardId: "assassin_01", lifeTotal: 0,
                   isEliminated: true, isUnveiled: true, joinedAt: Date()),
            Player(id: "p3", orderId: 3, userId: "u3", displayName: "Carol",
                   role: .guardian, identityCardId: nil, lifeTotal: 0,
                   isEliminated: true, isUnveiled: true, joinedAt: Date()),
        ]
        let vm = makeVM(players: players)
        vm.presentAbilityResolver()
        #expect(vm.pendingAbilityResolution?.candidatePlayers.map(\.id) == ["p2"])
    }
}
