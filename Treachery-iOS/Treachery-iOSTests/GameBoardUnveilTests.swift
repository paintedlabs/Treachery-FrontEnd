import Combine
import Testing
import Foundation
@testable import Treachery_iOS

/// How an unveil settles when its call and the players snapshot disagree.
/// The server can unveil the player and its reply still be lost, and the
/// snapshot that shows the unveil can come before the reply or after the
/// reveal. Uses the production initializer, so the players listener is
/// attached, and drives it through the mock.
@MainActor
struct GameBoardUnveilTests {

    private struct ReplyLost: Error {}

    private static let failureMessage = "Couldn't unveil your identity. Check your connection and try again."

    // MARK: - Helpers

    /// The Leader u0, and the signed-in u1 holding The Metamorph: unveiled
    /// when `unveiled`, and eliminated, which unveils them too, when
    /// `eliminated`.
    private func players(unveiled: Bool = false, eliminated: Bool = false) -> [Player] {
        [
            Player(
                id: "p0", orderId: 0, userId: "u0", displayName: "Host",
                role: .leader, identityCardId: "leader_01", lifeTotal: 40,
                isEliminated: false, isUnveiled: false, joinedAt: Date(timeIntervalSince1970: 0)
            ),
            Player(
                id: "p1", orderId: 1, userId: "u1", displayName: "Alice",
                role: .traitor, identityCardId: "traitor_07", lifeTotal: eliminated ? 0 : 40,
                isEliminated: eliminated, isUnveiled: unveiled || eliminated,
                joinedAt: Date(timeIntervalSince1970: 0)
            ),
        ]
    }

    /// A Treachery game in progress, its first players snapshot showing u1
    /// still hidden.
    private func makeBoard(
        cloudFunctions: MockCloudFunctions,
        clock: TestClock
    ) -> (GameBoardViewModel, MockFirestoreManager) {
        let mockFS = MockFirestoreManager()
        mockFS.gamesToReturn["game1"] = Game(
            id: "game1", code: "ABCD", hostId: "u0", state: .inProgress,
            gameMode: .treachery, maxPlayers: 8, startingLife: 40,
            winningTeam: nil, playerIds: ["u0", "u1"],
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
        mockFS.playersToReturn = players()
        let vm = GameBoardViewModel(
            gameId: "game1",
            currentUserId: "u1",
            firestoreManager: mockFS,
            cloudFunctions: cloudFunctions,
            cardDatabase: CardDatabase(cards: []),
            planeDatabase: PlaneDatabase(cards: []),
            clock: clock
        )
        return (vm, mockFS)
    }

    /// Plays the reveal under way through to its end.
    private func finishReveal(of vm: GameBoardViewModel, on clock: TestClock) async throws {
        let reveal = try #require(vm.unveilReveal)
        await clock.waitForSleepers()
        clock.advance(by: GameBoardViewModel.UnveilProgress.flipDuration)
        await clock.waitForSleepers()
        clock.advance(by: GameBoardViewModel.UnveilProgress.bannerDuration)
        await reveal.value
    }

    // MARK: - A lost reply

    @Test(.timeLimit(.minutes(1)))
    func snapshotShowingTheUnveilAfterAFailedCallPlaysTheReveal() async throws {
        // The reply was lost, not the unveil. The board used to keep saying
        // it failed, beside a header showing them unveiled.
        let clock = TestClock()
        let cf = MockCloudFunctions()
        cf.errorToThrow = ReplyLost()
        let (vm, mockFS) = makeBoard(cloudFunctions: cf, clock: clock)

        await vm.unveilCurrentPlayer()?.value
        #expect(vm.unveilFailure == Self.failureMessage)

        mockFS.emitPlayers(.success(players(unveiled: true)), gameId: "game1")
        #expect(vm.unveilFailure == nil)
        #expect(vm.unveilProgress == .flippingAway)

        try await finishReveal(of: vm, on: clock)
        #expect(vm.unveilProgress == .idle)
        #expect(vm.pendingAbilityResolution?.abilityType == .metamorph)
    }

    @Test(.timeLimit(.minutes(1)))
    func failedCallAfterASnapshotShowedTheUnveilPlaysTheReveal() async throws {
        // The snapshot often arrives before the reply.
        let clock = TestClock()
        let cf = MockCloudFunctions()
        let gate = CallGate()
        cf.unveilPlayerGate = gate
        cf.errorToThrow = ReplyLost()
        let (vm, mockFS) = makeBoard(cloudFunctions: cf, clock: clock)

        let call = try #require(vm.unveilCurrentPlayer())
        await gate.waitForCall(from: call)
        mockFS.emitPlayers(.success(players(unveiled: true)), gameId: "game1")
        // The reply decides while it's awaited.
        #expect(vm.unveilProgress == .sending)

        gate.release()
        await call.value
        #expect(vm.unveilFailure == nil)
        #expect(vm.unveilProgress == .flippingAway)

        try await finishReveal(of: vm, on: clock)
        #expect(vm.unveilProgress == .idle)
    }

    @Test(.timeLimit(.minutes(1)))
    func eliminationSettlesAFailedUnveilWithNothingToReveal() async {
        // Being eliminated marks a player unveiled as well. The unveil
        // didn't go through, and the spectator bar says what did happen.
        let clock = TestClock()
        let cf = MockCloudFunctions()
        cf.errorToThrow = ReplyLost()
        let (vm, mockFS) = makeBoard(cloudFunctions: cf, clock: clock)

        await vm.unveilCurrentPlayer()?.value
        mockFS.emitPlayers(.success(players(eliminated: true)), gameId: "game1")

        #expect(vm.unveilProgress == .idle)
        #expect(vm.unveilReveal == nil)
        #expect(clock.pendingDeadlines.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func failureStaysUntilSettledOrTriedAgain() async throws {
        let clock = TestClock()
        let cf = MockCloudFunctions()
        cf.errorToThrow = ReplyLost()
        let (vm, mockFS) = makeBoard(cloudFunctions: cf, clock: clock)

        await vm.unveilCurrentPlayer()?.value
        // A snapshot that doesn't show the unveil leaves the failure up.
        mockFS.emitPlayers(.success(players()), gameId: "game1")
        #expect(vm.unveilFailure == Self.failureMessage)
        #expect(vm.offersUnveil)

        cf.errorToThrow = nil
        let retry = try #require(vm.unveilCurrentPlayer())
        #expect(vm.unveilFailure == nil)
        await retry.value
        #expect(vm.unveilProgress == .flippingAway)
    }

    // MARK: - A late snapshot

    @Test(.timeLimit(.minutes(1)))
    func unveilStaysOffUntilASnapshotShowsIt() async throws {
        // Unveil came back once the reveal ended, and the server refused a
        // second tap until the snapshot caught up: "Already unveiled."
        let clock = TestClock()
        let cf = MockCloudFunctions()
        let (vm, mockFS) = makeBoard(cloudFunctions: cf, clock: clock)

        await vm.unveilCurrentPlayer()?.value
        try await finishReveal(of: vm, on: clock)
        #expect(vm.unveilProgress == .awaitingSnapshot)
        #expect(!vm.offersUnveil)
        let again = vm.unveilCurrentPlayer()
        #expect(again == nil)

        mockFS.emitPlayers(.success(players(unveiled: true)), gameId: "game1")
        #expect(vm.unveilProgress == .idle)
        #expect(cf.unveilPlayerCalls == ["game1"])
    }

    // MARK: - A game that ends

    @Test(.timeLimit(.minutes(1)))
    func aRevealWhoseGameEndsDuringTheFlipNeverShowsTheBanner() async throws {
        // Another player's lethal change ends the game while the header
        // turns. Game Over covers the board, so the banner, and "Identity
        // revealed" with it, would only play behind the results.
        let clock = TestClock()
        let cf = MockCloudFunctions()
        let (vm, mockFS) = makeBoard(cloudFunctions: cf, clock: clock)
        var progress: [GameBoardViewModel.UnveilProgress] = []
        let subscription = vm.$unveilProgress.sink { progress.append($0) }
        defer { subscription.cancel() }

        await vm.unveilCurrentPlayer()?.value
        #expect(vm.unveilProgress == .flippingAway)
        let reveal = try #require(vm.unveilReveal)
        var finished = try #require(mockFS.gamesToReturn["game1"])
        finished.state = .finished
        mockFS.emitGame(.loaded(finished), gameId: "game1")

        await clock.waitForSleepers()
        clock.advance(by: GameBoardViewModel.UnveilProgress.flipDuration)
        await reveal.value

        #expect(!progress.contains(.revealing))
        #expect(vm.unveilProgress == .awaitingSnapshot)
        // It ends there, without waiting out the banner, and opens no sheet.
        #expect(clock.pendingDeadlines.isEmpty)
        #expect(vm.pendingAbilityResolution == nil)
    }
}
