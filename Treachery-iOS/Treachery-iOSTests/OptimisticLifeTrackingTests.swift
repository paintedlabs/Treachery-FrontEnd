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
            planeDatabase: PlaneDatabase(cards: [])
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
}
