import Combine
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

    /// Waits on the clock end at once, unless a test passes a `TestClock` to
    /// step through them.
    private func makeVM(
        game: Game? = nil,
        players: [Player]? = nil,
        currentUserId: String? = "u1",
        cloudFunctions: MockCloudFunctions = MockCloudFunctions(),
        firestoreManager: MockFirestoreManager = MockFirestoreManager(),
        clock: any Clock<Duration> = ImmediateClock()
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
            planeDatabase: PlaneDatabase(cards: []),
            clock: clock
        )
        return (vm, cloudFunctions, firestoreManager)
    }

    // MARK: - unveilCurrentPlayer

    /// Unveils, then waits for the call and for the reveal it starts, if
    /// any.
    private func unveil(_ vm: GameBoardViewModel) async {
        await vm.unveilCurrentPlayer()?.value
        await vm.unveilReveal?.value
    }

    /// makePlayers, with the signed-in u1 holding The Metamorph, still
    /// hidden.
    private func metamorphPlayers() -> [Player] {
        var players = makePlayers()
        players[1] = Player(
            id: "p1", orderId: 1, userId: "u1", displayName: "Alice",
            role: .traitor, identityCardId: "traitor_07", lifeTotal: 40,
            isEliminated: false, isUnveiled: false, joinedAt: Date()
        )
        return players
    }

    @Test func unveilCallsCloudFunction() async {
        let (vm, cf, _) = makeVM()
        await unveil(vm)
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
        await unveil(vm)
        #expect(cf.unveilPlayerCalls.isEmpty)
    }

    @Test func unveilDoesNothingWhenNoCurrentPlayer() async {
        let (vm, cf, _) = makeVM(currentUserId: nil)
        await unveil(vm)
        #expect(cf.unveilPlayerCalls.isEmpty)
    }

    @Test func unveilSetsErrorOnFailure() async {
        let cf = MockCloudFunctions()
        cf.errorToThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "network error"])
        let (vm, _, _) = makeVM(cloudFunctions: cf)
        await unveil(vm)
        // A plain sentence, never the SDK's description, kept apart from
        // the other actions' errors so a snapshot can settle it.
        #expect(vm.unveilFailure == "Couldn't unveil your identity. Check your connection and try again.")
        #expect(vm.errorMessage == nil)
        // They can try again.
        #expect(vm.offersUnveil)
    }

    @Test func unveilIsNotHeldUpByAnotherAction() async {
        // It used to share isPending, and return without a word while, say,
        // a phenomenon was resolving.
        let (vm, cf, _) = makeVM()
        vm.isPending = true
        await unveil(vm)
        #expect(cf.unveilPlayerCalls == ["game1"])
    }

    @Test func unveilDoesNothingWhenLeader() async {
        // A Leader is always face-up, and unveilPlayer refuses them ("Leader
        // is always visible."). Only the Action Bar used to hold this back;
        // the view model sent it.
        let (vm, cf, _) = makeVM(currentUserId: "host1") // host is leader
        await unveil(vm)
        #expect(!vm.offersUnveil)
        #expect(cf.unveilPlayerCalls.isEmpty)
    }

    // MARK: - Unveil reveal

    @Test(.timeLimit(.minutes(1)))
    func revealPlaysOnlyOnceTheServerHasUnveiled() async throws {
        let clock = TestClock()
        let cf = MockCloudFunctions()
        let gate = CallGate()
        cf.unveilPlayerGate = gate
        let (vm, _, _) = makeVM(cloudFunctions: cf, clock: clock)
        let progress = UnveilProgressRecorder(vm)

        let call = try #require(vm.unveilCurrentPlayer())
        await gate.waitForCall(from: call)
        // Nothing turns while the call is under way.
        #expect(vm.unveilProgress == .sending)
        #expect(vm.unveilReveal == nil)
        #expect(clock.pendingDeadlines.isEmpty)

        gate.release()
        await call.value
        let reveal = try #require(vm.unveilReveal)
        await clock.waitForSleepers()
        #expect(vm.unveilProgress == .flippingAway)
        #expect(clock.pendingDeadlines == [.milliseconds(300)])

        clock.advance(by: .milliseconds(300))
        await clock.waitForSleepers()
        #expect(vm.unveilProgress == .revealing)
        #expect(clock.pendingDeadlines == [.milliseconds(2_300)])

        clock.advance(by: .seconds(2))
        await reveal.value
        // No players snapshot has shown the unveil here, so Unveil stays
        // off; see GameBoardUnveilTests.
        #expect(progress.values == [.idle, .sending, .flippingAway, .revealing, .awaitingSnapshot])
    }

    @Test(.timeLimit(.minutes(1)))
    func failedUnveilPlaysNoReveal() async {
        let clock = TestClock()
        let cf = MockCloudFunctions()
        cf.errorToThrow = URLError(.notConnectedToInternet)
        let (vm, _, _) = makeVM(cloudFunctions: cf, clock: clock)
        let progress = UnveilProgressRecorder(vm)

        await vm.unveilCurrentPlayer()?.value

        // No flip and no banner: only the error says what happened.
        let message = "Couldn't unveil your identity. Check your connection and try again."
        #expect(progress.values == [.idle, .sending, .failed(message: message)])
        #expect(vm.unveilReveal == nil)
        #expect(clock.pendingDeadlines.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func repeatUnveilWhileOneIsUnderWayIsIgnored() async throws {
        let cf = MockCloudFunctions()
        let gate = CallGate()
        cf.unveilPlayerGate = gate
        let (vm, _, _) = makeVM(cloudFunctions: cf)

        let first = try #require(vm.unveilCurrentPlayer())
        await gate.waitForCall(from: first)
        // The gate holds only the first call, so a repeat that slipped
        // through would be counted rather than wait forever.
        let repeated = vm.unveilCurrentPlayer()
        gate.release()
        await first.value
        await repeated?.value

        #expect(repeated == nil)
        #expect(gate.arrivals == 1)
        #expect(cf.unveilPlayerCalls == ["game1"])
    }

    @Test(.timeLimit(.minutes(1)))
    func abilitySheetOpensOnceTheRevealIsOver() async throws {
        let clock = TestClock()
        let (vm, _, _) = makeVM(players: metamorphPlayers(), clock: clock)

        await vm.unveilCurrentPlayer()?.value
        let reveal = try #require(vm.unveilReveal)
        await clock.waitForSleepers()
        clock.advance(by: .milliseconds(300))
        await clock.waitForSleepers()
        // The sheet would cover the reveal.
        #expect(vm.unveilProgress == .revealing)
        #expect(vm.pendingAbilityResolution == nil)

        clock.advance(by: .seconds(2))
        await reveal.value
        #expect(vm.pendingAbilityResolution?.abilityType == .metamorph)
    }

    @Test(.timeLimit(.minutes(1)))
    func gameEndingDuringTheRevealOpensNoAbilitySheet() async throws {
        // Game Over is up by then, and resolveMetamorph would refuse: "Game
        // is not in progress." The game ends during the banner; one that
        // ends during the flip ends the reveal there (GameBoardUnveilTests).
        let clock = TestClock()
        let (vm, _, _) = makeVM(players: metamorphPlayers(), clock: clock)

        await vm.unveilCurrentPlayer()?.value
        let reveal = try #require(vm.unveilReveal)
        await clock.waitForSleepers()
        clock.advance(by: .milliseconds(300))
        await clock.waitForSleepers()
        vm.game?.state = .finished
        clock.advance(by: .seconds(2))
        await reveal.value

        #expect(vm.unveilReveal == nil)
        #expect(vm.pendingAbilityResolution == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func boardGoingAwayEndsTheReveal() async {
        // The reveal ran on GCD timers that outlived the board. The view
        // model owns it now, and it ends with the view model.
        let clock = TestClock()
        weak var weakVM: GameBoardViewModel?
        var reveal: Task<Void, Never>?
        do {
            let (vm, _, _) = makeVM(players: metamorphPlayers(), clock: clock)
            weakVM = vm
            await vm.unveilCurrentPlayer()?.value
            reveal = vm.unveilReveal
            await clock.waitForSleepers()
        }

        // Nothing kept the view model alive, the reveal included, and its
        // going away cancelled the reveal, with its wait on the clock.
        #expect(weakVM == nil)
        #expect(reveal?.isCancelled == true)
        #expect(clock.pendingDeadlines.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func boardCanGoAwayWhileTheUnveilIsSent() async {
        let clock = TestClock()
        let cf = MockCloudFunctions()
        let gate = CallGate()
        cf.unveilPlayerGate = gate
        weak var weakVM: GameBoardViewModel?
        var call: Task<Void, Never>?
        do {
            let (vm, _, _) = makeVM(cloudFunctions: cf, clock: clock)
            weakVM = vm
            call = vm.unveilCurrentPlayer()
            if let call { await gate.waitForCall(from: call) }
        }

        // The call holds what it needs, not the view model.
        #expect(weakVM == nil)
        gate.release()
        await call?.value
        // It finished, with no board left to play the reveal on.
        #expect(cf.unveilPlayerCalls == ["game1"])
        #expect(clock.pendingDeadlines.isEmpty)
    }

    @Test func unveilingACardSwappedInOpensNoAbilitySheet() async {
        // A Puppet Master handed The Metamorph to a Guardian, whose
        // resolveMetamorph the server would refuse.
        var players = makePlayers()
        players[1] = Player(
            id: "p1", orderId: 1, userId: "u1", displayName: "Alice",
            role: .traitor, identityCardId: "traitor_07", lifeTotal: 40,
            isEliminated: false, isUnveiled: false, joinedAt: Date(),
            originalIdentityCardId: "guardian_03"
        )
        let (vm, cf, _) = makeVM(players: players)

        await unveil(vm)

        #expect(cf.unveilPlayerCalls == ["game1"])
        #expect(vm.pendingAbilityResolution == nil)
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
        // A plain sentence, never the SDK's description.
        #expect(vm.errorMessage == "Couldn't forfeit the game. Check your connection and try again.")
    }

    // MARK: - rollDie

    @Test func rollDieCallsCloudFunction() async {
        let game = makeSampleGame(gameMode: .treacheryPlanechase)
        let cf = MockCloudFunctions()
        cf.rollPlanarDieResult = "planeswalk"
        // A clock that never moves keeps the result up.
        let (vm, _, _) = makeVM(game: game, cloudFunctions: cf, clock: TestClock())
        await vm.rollDie()
        #expect(vm.dieRollResult == "planeswalk")
    }

    @Test func rollDieDoesNothingWhenAlreadyRolling() async {
        let (vm, cf, _) = makeVM()
        // Simulate already rolling
        vm.isRollingDie = true
        await vm.rollDie()
        #expect(cf.rollPlanarDieCalls.isEmpty)
        #expect(vm.dieRollResult == nil)
    }

    @Test func rollDieSetsErrorOnFailure() async {
        let cf = MockCloudFunctions()
        cf.errorToThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "die error"])
        let (vm, _, _) = makeVM(cloudFunctions: cf)
        await vm.rollDie()
        // A plain sentence, never the SDK's description.
        #expect(vm.errorMessage == "Couldn't roll the planar die. Check your connection and try again.")
    }

    @Test(.timeLimit(.minutes(1)))
    func dieResultClearsAfterThreeSeconds() async throws {
        let clock = TestClock()
        let cf = MockCloudFunctions()
        cf.rollPlanarDieResult = "chaos"
        let (vm, _, _) = makeVM(game: makeSampleGame(gameMode: .planechase), cloudFunctions: cf, clock: clock)

        await vm.rollDie()
        let clear = try #require(vm.dieResultClear)
        await clock.waitForSleepers()
        #expect(vm.dieRollResult == "chaos")
        #expect(clock.pendingDeadlines == [.seconds(3)])

        clock.advance(by: .seconds(3))
        await clear.value
        #expect(vm.dieRollResult == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func quickSecondRollKeepsItsResultForItsOwnThreeSeconds() async throws {
        // The first roll's clear used to run regardless, and took the second
        // result down a second after it appeared.
        let clock = TestClock()
        let cf = MockCloudFunctions()
        let (vm, _, _) = makeVM(game: makeSampleGame(gameMode: .planechase), cloudFunctions: cf, clock: clock)

        cf.rollPlanarDieResult = "chaos"
        await vm.rollDie()
        let firstClear = try #require(vm.dieResultClear)
        await clock.waitForSleepers()
        clock.advance(by: .seconds(2))

        cf.rollPlanarDieResult = "planeswalk"
        await vm.rollDie()
        let secondClear = try #require(vm.dieResultClear)
        await clock.waitForSleepers()
        // When the first result would have come down.
        clock.advance(by: .seconds(1))
        await firstClear.value
        #expect(vm.dieRollResult == "planeswalk")
        #expect(clock.pendingDeadlines == [.seconds(5)])

        clock.advance(by: .seconds(2))
        await secondClear.value
        #expect(vm.dieRollResult == nil)
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
        #expect(vm.errorMessage == "Couldn't end the game. Check your connection and try again.")
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
        #expect(vm.errorMessage == "Couldn't resolve the phenomenon. Check your connection and try again.")
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

/// Every value `unveilProgress` takes, in order, starting with the one it has
/// when recording starts.
@MainActor
private final class UnveilProgressRecorder {
    private(set) var values: [GameBoardViewModel.UnveilProgress] = []
    private var subscription: AnyCancellable?

    init(_ viewModel: GameBoardViewModel) {
        subscription = viewModel.$unveilProgress.sink { [weak self] progress in
            self?.values.append(progress)
        }
    }
}
