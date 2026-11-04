import Testing
import Foundation
@testable import Treachery_iOS

@MainActor
struct OptimisticLifeTrackingTests {

    // MARK: - Helpers

    private func makePlayers(lifeTotals: [Int] = [40, 40, 40]) -> [Player] {
        lifeTotals.enumerated().map { i, life in
            Player(
                id: "p\(i)", orderId: i, userId: "u\(i)", displayName: "Player \(i)",
                role: .guardian, identityCardId: "card\(i)", lifeTotal: life,
                isEliminated: false, isUnveiled: false, joinedAt: Date()
            )
        }
    }

    private func makeEliminatedPlayer() -> Player {
        Player(
            id: "px", orderId: 99, userId: "ux", displayName: "Dead",
            role: .assassin, identityCardId: "cardx", lifeTotal: 0,
            isEliminated: true, isUnveiled: true, joinedAt: Date()
        )
    }

    private func makeVM(
        players: [Player]? = nil,
        cloudFunctions: MockCloudFunctions = MockCloudFunctions()
    ) -> (GameBoardViewModel, MockCloudFunctions) {
        let p = players ?? makePlayers()
        let game = Game(
            id: "game1", code: "ABCD", hostId: "u0", state: .inProgress,
            gameMode: .treachery, maxPlayers: 8, startingLife: 40,
            winningTeam: nil, playerIds: p.map(\.userId),
            createdAt: Date()
        )
        let vm = GameBoardViewModel(
            gameId: game.id,
            previewPlayers: p,
            previewGame: game,
            currentUserId: "u0",
            firestoreManager: MockFirestoreManager(),
            cloudFunctions: cloudFunctions,
            cardDatabase: CardDatabase(cards: []),
            planeDatabase: PlaneDatabase(cards: []),
            clock: TestClock()
        )
        return (vm, cloudFunctions)
    }

    // MARK: - Basic Optimistic Updates

    @Test func singleAdjustmentShowsOptimistically() {
        let (vm, _) = makeVM()
        vm.adjustLife(for: "p0", by: 5)
        let player = vm.players.first { $0.id == "p0" }
        #expect(player?.lifeTotal == 45)
    }

    @Test func negativeAdjustmentShowsOptimistically() {
        let (vm, _) = makeVM()
        vm.adjustLife(for: "p0", by: -3)
        let player = vm.players.first { $0.id == "p0" }
        #expect(player?.lifeTotal == 37)
    }

    @Test func multipleAdjustmentsAccumulate() {
        let (vm, _) = makeVM()
        vm.adjustLife(for: "p0", by: 1)
        vm.adjustLife(for: "p0", by: 1)
        vm.adjustLife(for: "p0", by: -1)
        let player = vm.players.first { $0.id == "p0" }
        #expect(player?.lifeTotal == 41) // 40 + 1 + 1 - 1
    }

    @Test func adjustLifeClampedToZero() {
        let players = makePlayers(lifeTotals: [2, 40, 40])
        let (vm, _) = makeVM(players: players)
        vm.adjustLife(for: "p0", by: -10)
        let player = vm.players.first { $0.id == "p0" }
        #expect(player?.lifeTotal == 0)
    }

    @Test func adjustLifeIgnoresEliminatedPlayer() {
        var players = makePlayers()
        players.append(makeEliminatedPlayer())
        let (vm, _) = makeVM(players: players)
        vm.adjustLife(for: "px", by: 5)
        let player = vm.players.first { $0.id == "px" }
        #expect(player?.lifeTotal == 0) // unchanged
    }

    @Test func adjustLifeIgnoresUnknownPlayerId() {
        let (vm, _) = makeVM()
        let countBefore = vm.players.count
        vm.adjustLife(for: "nonexistent", by: 5)
        #expect(vm.players.count == countBefore) // no crash, no change
    }

    @Test func independentPlayersHaveIndependentDeltas() {
        let (vm, _) = makeVM()
        vm.adjustLife(for: "p0", by: 5)
        vm.adjustLife(for: "p1", by: -3)
        let p0 = vm.players.first { $0.id == "p0" }
        let p1 = vm.players.first { $0.id == "p1" }
        let p2 = vm.players.first { $0.id == "p2" }
        #expect(p0?.lifeTotal == 45)
        #expect(p1?.lifeTotal == 37)
        #expect(p2?.lifeTotal == 40) // untouched
    }

    @Test func adjustLifeClearsError() {
        let (vm, _) = makeVM()
        vm.errorMessage = "old error"
        vm.adjustLife(for: "p0", by: 1)
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Debounce

    @Test(.timeLimit(.minutes(1)))
    func rapidTapsBecomeOneCall() async {
        let board = LifeBoard()
        for _ in 0..<3 {
            board.vm.adjustLife(for: "p0", by: -1)
            await board.clock.waitForSleepers()
            board.clock.advance(by: .milliseconds(400))
        }
        // Each tap restarted the debounce, so nothing has gone out yet.
        #expect(board.clock.pendingDeadlines == [.milliseconds(1_300)])
        #expect(board.vm.lifeChangeSends.isEmpty)

        await board.endDebounces()
        await board.finishSends()

        #expect(board.functions.adjustLifeCalls.map(\.amount) == [-3])
        #expect(board.shown() == 37)
    }

    @Test(.timeLimit(.minutes(1)))
    func twoPlayersChangesStayIndependent() async throws {
        let board = LifeBoard()
        board.vm.adjustLife(for: "p0", by: -2)
        await board.clock.waitForSleepers()
        board.clock.advance(by: .milliseconds(300))
        board.vm.adjustLife(for: "p1", by: 3)
        await board.clock.waitForSleepers(count: 2)

        // p1's tap didn't restart p0's debounce.
        let p0Debounce = try #require(board.vm.lifeChangeDebounces["p0"])
        board.clock.advance(by: .milliseconds(200))
        await p0Debounce.value
        await board.finishSends()
        #expect(board.functions.adjustLifeCalls.map(\.playerId) == ["p0"])

        let p1Debounce = try #require(board.vm.lifeChangeDebounces["p1"])
        board.clock.advance(by: .milliseconds(300))
        await p1Debounce.value
        await board.finishSends()
        #expect(board.functions.adjustLifeCalls.map(\.amount) == [-2, 3])

        // p0's echo settles p0 only; p1's change stays on screen.
        board.snapshot([38, 40, 40])
        #expect(board.shown("p0") == 38)
        #expect(board.shown("p1") == 43)
    }

    // MARK: - While a change is in flight

    @Test(.timeLimit(.minutes(1)))
    func aTapWhileAChangeIsInFlightShowsBothAmounts() async throws {
        let board = LifeBoard()
        let gate = board.holdCalls()
        board.vm.adjustLife(for: "p0", by: -3)
        await board.endDebounces()
        let send = try board.send()
        await gate.waitForCall(from: send)

        board.vm.adjustLife(for: "p0", by: -1)

        #expect(board.shown() == 36)
        gate.release()
    }

    @Test(.timeLimit(.minutes(1)))
    func otherPlayersChangesDuringTheFlightKeepTheTotal() async throws {
        // Both used to redraw p0 from the stale server total, 40.
        let board = LifeBoard()
        let gate = board.holdCalls()
        board.vm.adjustLife(for: "p0", by: -3)
        await board.endDebounces()
        let send = try board.send()
        await gate.waitForCall(from: send)

        board.snapshot([40, 35, 40]) // another device changes p1
        #expect(board.shown("p0") == 37)
        #expect(board.shown("p1") == 35)

        board.vm.adjustLife(for: "p2", by: -1) // a tap on someone else
        #expect(board.shown("p0") == 37)
        gate.release()
    }

    @Test(.timeLimit(.minutes(1)))
    func theEchoClearsTheInFlightAmount() async throws {
        let board = LifeBoard()
        let gate = board.holdCalls()
        board.vm.adjustLife(for: "p0", by: -3)
        await board.endDebounces()
        let send = try board.send()
        await gate.waitForCall(from: send)

        board.snapshot([37, 40, 40])
        #expect(board.shown() == 37) // not 34

        board.functions.adjustLifeNewLife = 37
        gate.release()
        await send.value
        #expect(board.shown() == 37)

        // Cleared, not kept for later: the next tap goes out on its own.
        board.vm.adjustLife(for: "p0", by: -1)
        board.functions.adjustLifeNewLife = 36
        await board.endDebounces()
        await board.finishSends()
        #expect(board.functions.adjustLifeCalls.map(\.amount) == [-3, -1])
        #expect(board.shown() == 36)
    }

    @Test(.timeLimit(.minutes(1)))
    func aResponseTheBoardAlreadyShowsClearsTheInFlightAmount() async throws {
        // Another device's +3 lands together with this -3, so the snapshot
        // stays at 40: only adjustLife's newLife shows the change is in.
        let board = LifeBoard()
        let gate = board.holdCalls()
        board.vm.adjustLife(for: "p0", by: -3)
        await board.endDebounces()
        let send = try board.send()
        await gate.waitForCall(from: send)
        board.snapshot([40, 40, 40])
        #expect(board.shown() == 37)

        board.functions.adjustLifeNewLife = 40
        gate.release()
        await send.value

        #expect(board.shown() == 40)
    }

    enum Arrival: CaseIterable {
        case echoFirst
        case responseFirst
    }

    @Test(.timeLimit(.minutes(1)), arguments: Arrival.allCases)
    func displayedTotalsNeverJumpBackwards(_ arrival: Arrival) async throws {
        let board = LifeBoard()
        let gate = board.holdCalls()
        var totals: [Int?] = []

        board.vm.adjustLife(for: "p0", by: -1)
        totals.append(board.shown())
        board.vm.adjustLife(for: "p0", by: -1)
        totals.append(board.shown())
        await board.endDebounces()
        let firstSend = try board.send()
        await gate.waitForCall(from: firstSend)
        totals.append(board.shown())

        board.snapshot([40, 35, 40]) // another device changes p1
        totals.append(board.shown())
        board.vm.adjustLife(for: "p0", by: -1)
        totals.append(board.shown())

        board.functions.adjustLifeNewLife = 38
        switch arrival {
        case .echoFirst:
            board.snapshot([38, 35, 40])
            totals.append(board.shown())
            gate.release()
            await firstSend.value
            totals.append(board.shown())
        case .responseFirst:
            gate.release()
            await firstSend.value
            totals.append(board.shown())
            board.snapshot([38, 35, 40])
            totals.append(board.shown())
        }

        board.functions.adjustLifeNewLife = 37
        await board.endDebounces()
        await board.finishSends()
        totals.append(board.shown())
        board.snapshot([37, 35, 40])
        totals.append(board.shown())

        #expect(totals == [39, 38, 38, 38, 37, 37, 37, 37, 37])
        #expect(board.functions.adjustLifeCalls.map(\.amount) == [-2, -1])
    }

    // MARK: - Failure

    @Test(.timeLimit(.minutes(1)))
    func aFailureRevertsTheTotalAndShowsTheMessage() async throws {
        let board = LifeBoard()
        let gate = board.holdCalls()
        board.functions.errorToThrow = NSError(domain: "test", code: 1)
        board.vm.adjustLife(for: "p1", by: -3)
        await board.endDebounces()
        let send = try board.send(for: "p1")
        await gate.waitForCall(from: send)
        #expect(board.shown("p1") == 37)

        gate.release()
        await send.value

        #expect(board.shown("p1") == 40)
        #expect(board.vm.lifeChangeFailure == GameBoardViewModel.LifeChangeFailure(
            playerId: "p1",
            message: "Couldn't update Player 1's life. Check your connection and try again."
        ))
        // Not retried: nothing is left running that could send it again.
        #expect(board.vm.lifeChangeDebounces.isEmpty)
        #expect(board.vm.lifeChangeSends.isEmpty)
        #expect(board.clock.pendingDeadlines.isEmpty)
        #expect(gate.arrivals == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func aFailureAfterTheEchoDoesNotAskForTheChangeAgain() async throws {
        // The server applied the -3 and this device saw it, but the response
        // was lost: making the change again would take Player 0 to 34.
        let board = LifeBoard()
        let gate = board.holdCalls()
        board.functions.adjustLifeErrors = [NSError(domain: "test", code: 1)]
        board.vm.adjustLife(for: "p0", by: -3)
        await board.endDebounces()
        let send = try board.send()
        await gate.waitForCall(from: send)
        board.snapshot([37, 40, 40])

        gate.release()
        await send.value

        #expect(board.shown() == 37)
        #expect(board.vm.lifeChangeFailure?.message == "Couldn't confirm Player 0's life change. Check the total before changing it again.")
    }

    @Test(.timeLimit(.minutes(1)))
    func aFailureStaysExplainedUntilThatPlayerIsChangedAgain() async {
        let board = LifeBoard()
        board.functions.adjustLifeErrors = [NSError(domain: "test", code: 1)]
        board.vm.adjustLife(for: "p1", by: -3)
        await board.endDebounces()
        await board.finishSends()
        let message = "Couldn't update Player 1's life. Check your connection and try again."
        #expect(board.vm.lifeChangeFailure?.message == message)

        // Changing someone else doesn't say why Player 1 went back to 40.
        board.vm.adjustLife(for: "p2", by: -1)
        #expect(board.vm.lifeChangeFailure?.message == message)

        board.vm.adjustLife(for: "p1", by: -3)
        #expect(board.vm.lifeChangeFailure == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func tapsMadeDuringAFailedCallGoOutOnTheirOwn() async throws {
        let board = LifeBoard()
        let gate = board.holdCalls()
        board.functions.errorToThrow = NSError(domain: "test", code: 1)
        board.vm.adjustLife(for: "p0", by: -3)
        await board.endDebounces()
        let send = try board.send()
        await gate.waitForCall(from: send)
        board.vm.adjustLife(for: "p0", by: -1)

        gate.release()
        await send.value
        #expect(board.shown() == 39)

        board.functions.errorToThrow = nil
        await board.endDebounces()
        await board.finishSends()
        #expect(board.functions.adjustLifeCalls.map(\.amount) == [-1])
        #expect(gate.arrivals == 2)
        #expect(board.shown() == 39)
    }

    // MARK: - Leaving the board

    @Test(.timeLimit(.minutes(1)))
    func leavingTheBoardSendsPendingTaps() async {
        let board = LifeBoard()
        board.vm.adjustLife(for: "p0", by: -2)
        board.vm.adjustLife(for: "p2", by: 1)

        for send in board.vm.sendPendingLifeChanges() {
            await send.value
        }

        let calls = board.functions.adjustLifeCalls.map { "\($0.playerId) \($0.amount)" }
        #expect(calls.sorted() == ["p0 -2", "p2 1"])
        // Their debounces are stopped, so the taps can't go out a second time.
        #expect(board.vm.lifeChangeDebounces.isEmpty)
        #expect(board.clock.pendingDeadlines.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func leavingSendsTapsMadeWhileACallIsUnderWay() async throws {
        let board = LifeBoard()
        let gate = board.holdCalls()
        board.vm.adjustLife(for: "p0", by: -3)
        await board.endDebounces()
        let send = try board.send()
        await gate.waitForCall(from: send)
        board.vm.adjustLife(for: "p0", by: -1)

        // The gate holds only the first call, so this one goes straight out.
        for leaving in board.vm.sendPendingLifeChanges() {
            await leaving.value
        }
        gate.release()
        await send.value

        #expect(board.functions.adjustLifeCalls.map(\.amount) == [-1, -3])
    }

    @Test(.timeLimit(.minutes(1)))
    func pendingTapsGoOutEvenOnceTheBoardIsGone() async {
        let gate = CallGate()
        let functions = MockCloudFunctions()
        functions.adjustLifeGate = gate
        var vm: GameBoardViewModel? = LifeBoard.makeViewModel(functions: functions)
        weak var weakVM: GameBoardViewModel?
        weakVM = vm
        vm?.adjustLife(for: "p0", by: -2)

        let sends = vm?.sendPendingLifeChanges() ?? []
        vm = nil
        #expect(weakVM == nil)

        for send in sends {
            await gate.waitForCall(from: send)
        }
        gate.release()
        for send in sends {
            await send.value
        }
        #expect(functions.adjustLifeCalls.map(\.amount) == [-2])
    }
}

// MARK: - Taps held until the change before them settles

/// In each of these the -1's debounce ends before the -3 has settled, so
/// the -1 waits; nothing but the -3 settling may send it.
@MainActor
struct HeldLifeTapTests {

    @Test(.timeLimit(.minutes(1)))
    func aHeldTapGoesOutWhenTheEchoSettlesAConfirmedChange() async throws {
        let board = LifeBoard()
        let gate = board.holdCalls()
        let send = try await board.holdTapBehindAChangeInFlight()

        // The response comes first: the -3 stays on screen until its echo,
        // and the -1 keeps waiting.
        board.functions.adjustLifeNewLife = 37
        gate.release()
        await send.value
        #expect(board.vm.lifeChangeSends.isEmpty)
        #expect(board.vm.lifeChangeEchoWaits["p0"] != nil)
        #expect(board.functions.adjustLifeCalls.map(\.amount) == [-3])
        #expect(board.shown() == 36)

        board.functions.adjustLifeNewLife = 36
        board.snapshot([37, 40, 40])
        #expect(board.vm.lifeChangeSends["p0"] != nil)
        // The echo ended the wait for it.
        #expect(board.vm.lifeChangeEchoWaits.isEmpty)
        #expect(board.clock.pendingDeadlines.isEmpty)
        await board.finishSends()
        #expect(board.functions.adjustLifeCalls.map(\.amount) == [-3, -1])
        #expect(board.shown() == 36)
    }

    @Test(.timeLimit(.minutes(1)))
    func aHeldTapGoesOutWhenTheResponseSettlesAChangeTheEchoShowed() async throws {
        let board = LifeBoard()
        let gate = board.holdCalls()
        let send = try await board.holdTapBehindAChangeInFlight()

        // The echo comes first, but the -3's call is still out.
        board.snapshot([37, 40, 40])
        #expect(board.vm.lifeChangeSends.count == 1)
        #expect(gate.arrivals == 1)
        #expect(board.shown() == 36)

        gate.release()
        await send.value
        await board.finishSends()
        #expect(board.functions.adjustLifeCalls.map(\.amount) == [-3, -1])
        #expect(gate.arrivals == 2)
        #expect(board.shown() == 36)
    }

    @Test(.timeLimit(.minutes(1)))
    func aHeldTapGoesOutWhenTheChangeAheadOfItFails() async throws {
        let board = LifeBoard()
        let gate = board.holdCalls()
        board.functions.adjustLifeErrors = [NSError(domain: "test", code: 1)]
        let send = try await board.holdTapBehindAChangeInFlight()

        gate.release()
        await send.value
        await board.finishSends()

        // The -3 failed and is never resent; the -1 went out on its own.
        #expect(board.functions.adjustLifeCalls.map(\.amount) == [-1])
        #expect(gate.arrivals == 2)
        #expect(board.shown() == 39)
    }

    @Test(.timeLimit(.minutes(1)))
    func aConfirmedChangeNoSnapshotShowsComesOffAfterTheEchoTimeout() async throws {
        // This -3 lands, then another device's +3, and this device only gets
        // the snapshot with both: 40, the total the -3 was sent from.
        let board = LifeBoard()
        board.functions.adjustLifeNewLife = 37
        board.vm.adjustLife(for: "p0", by: -3)
        await board.endDebounces()
        await board.finishSends()
        board.snapshot([40, 40, 40])
        #expect(board.shown() == 37)

        board.vm.adjustLife(for: "p0", by: -1)
        await board.endDebounces()
        #expect(board.vm.lifeChangeSends.isEmpty)
        #expect(board.shown() == 36)

        // The wait runs from the response, at 0.5 s.
        let echoWait = try #require(board.vm.lifeChangeEchoWaits["p0"])
        let deadline = Duration.milliseconds(500) + GameBoardViewModel.lifeChangeEchoTimeout
        #expect(board.clock.pendingDeadlines == [deadline])
        board.functions.adjustLifeNewLife = 39
        board.clock.advance(by: deadline - board.clock.now.offset)
        await echoWait.value
        await board.finishSends()

        // The server's total stands, and the held tap went out from it.
        #expect(board.functions.adjustLifeCalls.map(\.amount) == [-3, -1])
        #expect(board.shown() == 39)
    }
}

// MARK: - Board

/// A board on the production initializer, so its players listener is
/// attached, with a clock the test moves and a server mock that can hold
/// adjustLife calls in flight.
@MainActor
private struct LifeBoard {
    let firestore = MockFirestoreManager()
    let functions = MockCloudFunctions()
    let clock = TestClock()
    let vm: GameBoardViewModel

    init() {
        vm = Self.makeViewModel(firestore: firestore, functions: functions, clock: clock)
    }

    /// Player i is "p<i>", named "Player i", with the i-th life total.
    static func players(_ lifeTotals: [Int]) -> [Player] {
        lifeTotals.enumerated().map { i, life in
            Player(
                id: "p\(i)", orderId: i, userId: "u\(i)", displayName: "Player \(i)",
                role: .guardian, identityCardId: nil, lifeTotal: life,
                isEliminated: false, isUnveiled: false, joinedAt: Date(timeIntervalSince1970: 0)
            )
        }
    }

    /// Three players at 40.
    static func makeViewModel(
        firestore: MockFirestoreManager = MockFirestoreManager(),
        functions: MockCloudFunctions,
        clock: TestClock = TestClock()
    ) -> GameBoardViewModel {
        firestore.gamesToReturn["game1"] = Game(
            id: "game1", code: "ABCD", hostId: "u0", state: .inProgress,
            gameMode: .treachery, maxPlayers: 8, startingLife: 40,
            winningTeam: nil, playerIds: ["u0", "u1", "u2"],
            createdAt: Date(timeIntervalSince1970: 0)
        )
        firestore.playersToReturn = players([40, 40, 40])
        return GameBoardViewModel(
            gameId: "game1",
            currentUserId: "u0",
            firestoreManager: firestore,
            cloudFunctions: functions,
            cardDatabase: CardDatabase(cards: []),
            planeDatabase: PlaneDatabase(cards: []),
            clock: clock
        )
    }

    /// Delivers a players snapshot with these life totals.
    func snapshot(_ lifeTotals: [Int]) {
        firestore.emitPlayers(.success(Self.players(lifeTotals)), gameId: "game1")
    }

    /// The life total the board shows for the player.
    func shown(_ playerId: String = "p0") -> Int? {
        vm.players.first { $0.id == playerId }?.lifeTotal
    }

    /// Holds the next adjustLife call until the test releases the gate.
    func holdCalls() -> CallGate {
        let gate = CallGate()
        functions.adjustLifeGate = gate
        return gate
    }

    /// The adjustLife call under way for the player.
    func send(for playerId: String = "p0") throws -> Task<Void, Never> {
        try #require(vm.lifeChangeSends[playerId])
    }

    /// Ends every running debounce, all started at the current time, and
    /// waits until each has started its send. Echo waits sleep on the same
    /// clock, so they're counted in; none is due this soon.
    func endDebounces() async {
        let debounces = Array(vm.lifeChangeDebounces.values)
        await clock.waitForSleepers(count: debounces.count + vm.lifeChangeEchoWaits.count)
        clock.advance(by: GameBoardViewModel.lifeChangeDebounce)
        for debounce in debounces {
            await debounce.value
        }
    }

    /// Sends p0 -3 and, while the gate holds that call, taps p0 -1 and ends
    /// its debounce. Returns the -3's send, with the -1 waiting behind it.
    func holdTapBehindAChangeInFlight() async throws -> Task<Void, Never> {
        vm.adjustLife(for: "p0", by: -3)
        await endDebounces()
        let inFlight = try send()
        let gate = try #require(functions.adjustLifeGate)
        await gate.waitForCall(from: inFlight)

        vm.adjustLife(for: "p0", by: -1)
        await endDebounces()
        #expect(vm.lifeChangeDebounces.isEmpty)
        #expect(vm.lifeChangeSends.count == 1)
        #expect(gate.arrivals == 1)
        #expect(shown() == 36)
        return inFlight
    }

    /// Waits for the calls under way, and any they lead to, to finish.
    func finishSends() async {
        for _ in 0..<10 {
            guard let send = vm.lifeChangeSends.values.first else { return }
            await send.value
        }
        Issue.record("Sends kept starting")
    }
}
