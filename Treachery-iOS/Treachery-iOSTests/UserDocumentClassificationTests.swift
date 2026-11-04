import Testing
import Foundation
import FirebaseFirestore
@testable import Treachery_iOS

/// The classifier behind provisioning's one rule: only a profile that
/// doesn't exist may be created. It runs on the fields a snapshot holds,
/// decoded with Firestore's own decoder, exactly as `getUserDocument(id:)`
/// and `getUser(id:)` use it.
@Suite("Classifying users/{uid}")
struct UserDocumentClassificationTests {

    private let createdAt = Timestamp(date: Date(timeIntervalSince1970: 1_700_000_000))

    private func classify(_ data: [String: Any]?) -> UserDocument {
        FirestoreManager.userDocument(fromData: data, id: "u1")
    }

    // MARK: - Missing

    @Test func noDocumentIsMissing() {
        #expect(isMissing(classify(nil)))
    }

    // MARK: - Incomplete

    @Test func emptyDocumentIsIncompleteNotMissing() {
        // The empty doc registerFcmToken used to create.
        #expect(missingFields(classify([:])) == [.displayName, .createdAt, .elo])
    }

    @Test func nullFieldsCountAsMissing() {
        let document = classify(["display_name": NSNull(), "created_at": createdAt, "elo": 1500])
        #expect(missingFields(document) == [.displayName])
    }

    @Test func profileWithoutCreatedAtIsIncomplete() {
        let document = classify(["display_name": "Ada", "friend_ids": ["f1"]])
        #expect(missingFields(document) == [.createdAt, .elo])
    }

    @Test func documentHoldingOnlyLeftoverContactDetailsIsIncomplete() {
        let document = classify(["email": "ada@example.com", "fcm_token": "token"])
        #expect(missingFields(document) == [.displayName, .createdAt, .elo])
    }

    // MARK: - Undecodable

    @Test func wrongTypeForANeededFieldIsUndecodable() {
        #expect(isUndecodable(classify(["display_name": 42, "created_at": createdAt])))
        #expect(isUndecodable(classify(["display_name": "Ada", "created_at": "2026-01-01"])))
        #expect(isUndecodable(classify(["display_name": "Ada", "created_at": createdAt, "friend_ids": "f1"])))
    }

    // MARK: - Complete

    @Test func fullProfileIsComplete() throws {
        let user = try #require(profile(classify([
            "display_name": "Ada",
            "created_at": createdAt,
            "friend_ids": ["f1"],
            "elo": 1620,
            "deck_stats": ["Krenko": ["elo": 1530, "wins": 3, "losses": 1, "games": 4]],
        ])))
        #expect(user.id == "u1")
        #expect(user.displayName == "Ada")
        #expect(user.createdAt == createdAt.dateValue())
        #expect(user.friendIds == ["f1"])
        #expect(user.elo == 1620)
        #expect(user.deckStats?["Krenko"]?.games == 4)
    }

    @Test func profileWithoutEloIsCompleteAtTheStartingRating() throws {
        let user = try #require(profile(classify(["display_name": "Ada", "created_at": createdAt])))
        #expect(user.elo == TreacheryUser.startingElo)
        #expect(user.friendIds.isEmpty)
    }

    @Test func legacyProfileStillHoldingContactDetailsIsComplete() throws {
        let user = try #require(profile(classify([
            "display_name": "Ada",
            "created_at": createdAt,
            "email": "ada@example.com",
            "phone_number": "+15551234567",
            "fcm_token": "token",
        ])))
        #expect(user.displayName == "Ada")
    }

    @Test func malformedDeckStatsEntryDoesNotMakeTheProfileUnreadable() throws {
        // A commander name containing "." was once written as a nested map.
        let user = try #require(profile(classify([
            "display_name": "Ada",
            "created_at": createdAt,
            "friend_ids": ["f1"],
            "elo": 1620,
            "deck_stats": [
                "Krenko": ["elo": 1530, "wins": 3, "losses": 1, "games": 4],
                "Mr": ["House, President and CEO": ["elo": 1510, "wins": 1, "losses": 0, "games": 1]],
            ],
        ])))
        #expect(user.elo == 1620)
        #expect(user.friendIds == ["f1"])
        #expect(user.deckStats.map { Set($0.keys) } == ["Krenko"])
    }

    // MARK: - Helpers

    private func isMissing(_ document: UserDocument) -> Bool {
        if case .missing = document { return true }
        return false
    }

    private func isUndecodable(_ document: UserDocument) -> Bool {
        if case .undecodable = document { return true }
        return false
    }

    private func missingFields(_ document: UserDocument) -> Set<ProfileField>? {
        if case .incomplete(let fields) = document { return fields }
        return nil
    }

    private func profile(_ document: UserDocument) -> TreacheryUser? {
        if case .complete(let user) = document { return user }
        return nil
    }
}
