//
//  TreacheryUser.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import Foundation
import os

struct DeckStat: Codable {
    var elo: Int
    var wins: Int
    var losses: Int
    var games: Int
}

/// A public profile, `users/{uid}`, which every signed-in user can read.
///
/// It has no email, phone number or FCM token on purpose. Those live only in
/// the owner-only `users/{uid}/private/data`. Profiles written before that
/// split still carry them until `functions/scripts/backfill-user-pii.js` runs;
/// decoding skips them. The signed-in user's own email and phone number come
/// from Firebase Auth.
struct TreacheryUser: Codable, Identifiable {
    /// The rating every profile starts with, and the one a profile without
    /// `elo` is read as.
    static let startingElo = 1500

    private static let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "Profile")

    var id: String
    var displayName: String
    var friendIds: [String]
    let createdAt: Date
    var elo: Int
    var deckStats: [String: DeckStat]?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case friendIds = "friend_ids"
        case createdAt = "created_at"
        case elo
        case deckStats = "deck_stats"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        displayName = try container.decode(String.self, forKey: .displayName)
        friendIds = try container.decodeIfPresent([String].self, forKey: .friendIds) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        elo = try container.decodeIfPresent(Int.self, forKey: .elo) ?? Self.startingElo
        deckStats = Self.readableDeckStats(in: container)
    }

    init(
        id: String,
        displayName: String,
        friendIds: [String],
        createdAt: Date,
        elo: Int = Self.startingElo,
        deckStats: [String: DeckStat]? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.friendIds = friendIds
        self.createdAt = createdAt
        self.elo = elo
        self.deckStats = deckStats
    }

    // MARK: - Deck Stats Decoding

    /// The entries of `deck_stats` that are complete `DeckStat`s. Any other
    /// entry is skipped rather than failing the whole profile, which would
    /// hide the user from friend lists and search and leave their Profile
    /// unreadable. Servers before 65d46e4 wrote a commander name containing
    /// "." as a nested map instead of a stat. Nil when `deck_stats` is
    /// absent or isn't a map.
    private static func readableDeckStats(in container: KeyedDecodingContainer<CodingKeys>) -> [String: DeckStat]? {
        guard let entries = try? container.nestedContainer(keyedBy: DeckName.self, forKey: .deckStats) else {
            return nil
        }
        let stats = entries.allKeys.reduce(into: [String: DeckStat]()) { stats, deck in
            stats[deck.stringValue] = try? entries.decode(DeckStat.self, forKey: deck)
        }
        let skipped = entries.allKeys.count - stats.count
        if skipped > 0 {
            logger.notice("Skipped \(skipped, privacy: .public) unreadable deck_stats entries")
        }
        return stats
    }

    /// A `deck_stats` key: the commander's name.
    private struct DeckName: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }
}
