import Testing
import Foundation
@testable import Treachery_iOS

/// How `getFriends` combines its reads, one per 30 friends: offline, an
/// empty answer from the cache only means nothing was cached, so it fails
/// only when no read found any friend.
@Suite("Friends read in batches")
struct FriendsReadTests {

    private typealias Read = FirestoreManager.FriendsRead

    /// More than 30 friends, offline, with only the first batch cached: the
    /// cached friends show rather than a failure.
    @Test func batchWithNothingCachedDoesNotHideTheFriendsFound() throws {
        let reads = [
            Read(friends: [friend("f1", named: "Cy"), friend("f2", named: "Ada")], isFromCache: true),
            Read(friends: [], isFromCache: true),
        ]

        let friends = try FirestoreManager.friends(from: reads)

        #expect(friends.map(\.id) == ["f2", "f1"])
    }

    @Test func noFriendCachedOfflineIsAFailureNotNoFriends() {
        let reads = [Read(friends: [], isFromCache: true), Read(friends: [], isFromCache: true)]

        #expect(throws: FirestoreReadError.nothingCachedOffline) {
            try FirestoreManager.friends(from: reads)
        }
    }

    /// One empty answer from the server doesn't vouch for a batch that
    /// answered from the cache.
    @Test func emptyAnswerIsTrustedOnlyWhenEveryBatchCameFromTheServer() throws {
        let partlyCached = [Read(friends: [], isFromCache: false), Read(friends: [], isFromCache: true)]
        #expect(throws: FirestoreReadError.nothingCachedOffline) {
            try FirestoreManager.friends(from: partlyCached)
        }

        let fromTheServer = [Read(friends: [], isFromCache: false), Read(friends: [], isFromCache: false)]
        #expect(try FirestoreManager.friends(from: fromTheServer).isEmpty)
    }

    @Test func friendsFromEveryBatchAreSortedByName() throws {
        let reads = [
            Read(friends: [friend("f1", named: "Dee")], isFromCache: false),
            Read(friends: [friend("f2", named: "Bo"), friend("f3", named: "Al")], isFromCache: false),
        ]

        #expect(try FirestoreManager.friends(from: reads).map(\.displayName) == ["Al", "Bo", "Dee"])
    }

    // MARK: - Fixtures

    private func friend(_ id: String, named displayName: String) -> TreacheryUser {
        TreacheryUser(id: id, displayName: displayName, friendIds: [], createdAt: Date(timeIntervalSince1970: 1_000_000))
    }
}
