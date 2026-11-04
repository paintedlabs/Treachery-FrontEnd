import Testing
import Foundation
@testable import Treachery_iOS

/// What FirestoreManager's listeners report for each snapshot. The screens'
/// listener tests inject these outcomes through the mock, so this is where
/// the decisions themselves run under test.
struct FirestoreListenerMappingTests {

    private struct DecodeError: Error {}

    private let game = Game(
        id: "game1", code: "ABCD", hostId: "u0", state: .waiting,
        gameMode: .treachery, maxPlayers: 8, startingLife: 40,
        winningTeam: nil, playerIds: ["u0"],
        createdAt: Date(timeIntervalSince1970: 1_000_000)
    )

    private func player(_ i: Int) -> Player {
        Player(
            id: "p\(i)", orderId: i, userId: "u\(i)", displayName: "Player \(i)",
            role: nil, identityCardId: nil, lifeTotal: 40,
            isEliminated: false, isUnveiled: false, joinedAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// A game snapshot with the server's word on it unless a test says
    /// otherwise.
    private func gameEvent(
        exists: Bool,
        isFromCache: Bool = false,
        hasPendingWrites: Bool = false,
        decoded: Result<Game, any Error>? = nil
    ) -> DocumentEvent<Game>? {
        FirestoreManager.gameEvent(
            exists: exists,
            isFromCache: isFromCache,
            hasPendingWrites: hasPendingWrites,
            decoded: decoded ?? .success(game)
        )
    }

    // MARK: - Game

    @Test func cacheOnlyMissIsNotReported() {
        // Offline, or never cached: not proof the game is gone.
        #expect(gameEvent(exists: false, isFromCache: true) == nil)
    }

    @Test func serverConfirmedMissIsMissing() {
        guard case .missing = gameEvent(exists: false) else {
            Issue.record("expected .missing")
            return
        }
    }

    @Test func missShowingAnUnacknowledgedLocalWriteIsNotReported() {
        // The server hasn't confirmed it yet; its acknowledgement arrives as
        // a metadata change.
        #expect(gameEvent(exists: false, hasPendingWrites: true) == nil)
    }

    @Test func serversConfirmationOfAMissGetsThrough() {
        // The confirmation often changes only the snapshot's metadata, which
        // the game listener hears only with metadata changes on. The cache's
        // miss comes first and is held back; the server's, otherwise the
        // same, is reported.
        #expect(FirestoreManager.gameListenerIncludesMetadataChanges)
        #expect(gameEvent(exists: false, isFromCache: true) == nil)
        guard case .missing = gameEvent(exists: false, isFromCache: false) else {
            Issue.record("expected .missing")
            return
        }
    }

    @Test(arguments: [true, false])
    func gameThatDecodesIsLoaded(isFromCache: Bool) {
        // A cached copy is still worth showing while the server catches up.
        guard case .loaded(let loaded) = gameEvent(exists: true, isFromCache: isFromCache) else {
            Issue.record("expected .loaded")
            return
        }
        #expect(loaded == game)
    }

    @Test func gameThatDoesNotDecodeIsUnreadable() {
        guard case .failed(.unreadable(let error)) = gameEvent(exists: true, decoded: .failure(DecodeError())) else {
            Issue.record("expected .failed(.unreadable)")
            return
        }
        #expect(error is DecodeError)
    }

    @Test func missingGameIsNeverDecoded() {
        var decodeCount = 0
        _ = FirestoreManager.gameEvent(exists: false, isFromCache: false, hasPendingWrites: false, decoded: {
            decodeCount += 1
            return .success(game)
        }())
        #expect(decodeCount == 0)
    }

    // MARK: - Players

    @Test func everyPlayerDecodesInOrder() throws {
        let result = FirestoreManager.playersResult(decoded: [.success(player(0)), .success(player(1))])
        #expect(try result.get().map(\.id) == ["p0", "p1"])
    }

    @Test func emptySnapshotHasNoPlayers() throws {
        #expect(try FirestoreManager.playersResult(decoded: []).get().isEmpty)
    }

    @Test func oneUndecodablePlayerMakesTheSnapshotUnreadable() {
        // Dropping that seat would remove a player from the board without a
        // word.
        let result = FirestoreManager.playersResult(decoded: [.success(player(0)), .failure(DecodeError()), .success(player(2))])
        guard case .failure(.unreadable(let error)) = result else {
            Issue.record("expected .failure(.unreadable)")
            return
        }
        #expect(error is DecodeError)
    }

    // MARK: - Errors

    /// Shaped like the errors the Firestore SDK reports: its domain and a
    /// FirestoreErrorCode raw value.
    private func firestoreError(code: Int) -> NSError {
        NSError(domain: "FIRFirestoreErrorDomain", code: code)
    }

    @Test func refusedReadIsAccessDenied() {
        // A players read once the user is no longer in player_ids. Retrying
        // can't help, so it mustn't look like a dropped connection.
        guard case .accessDenied = FirestoreManager.listenerFailure(for: firestoreError(code: 7)) else {
            Issue.record("expected .accessDenied")
            return
        }
    }

    @Test(arguments: [4, 13, 14])
    func otherFirestoreErrorsStopTheListener(code: Int) {
        // Deadline exceeded, internal, unavailable: worth trying again.
        guard case .listenerStopped = FirestoreManager.listenerFailure(for: firestoreError(code: code)) else {
            Issue.record("expected .listenerStopped")
            return
        }
    }

    @Test func permissionDeniedCodeFromAnotherDomainStopsTheListener() {
        let error = NSError(domain: "com.firebase.functions", code: 7)
        guard case .listenerStopped = FirestoreManager.listenerFailure(for: error) else {
            Issue.record("expected .listenerStopped")
            return
        }
    }
}
