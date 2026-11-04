import Testing
import Foundation
@testable import Treachery_iOS

/// A board on the production initializer, so its players listener is
/// attached, with a clock the test moves and a server mock that can hold
/// adjustLife calls in flight.
@MainActor
struct LifeBoard {
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
