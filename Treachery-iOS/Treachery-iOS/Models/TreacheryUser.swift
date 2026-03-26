//
//  TreacheryUser.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import Foundation

struct DeckStat: Codable {
    var elo: Int
    var wins: Int
    var losses: Int
    var games: Int
}

struct TreacheryUser: Codable, Identifiable {
    var id: String
    var displayName: String
    let email: String?
    var phoneNumber: String?
    var friendIds: [String]
    var fcmToken: String?
    let createdAt: Date
    var elo: Int
    var deckStats: [String: DeckStat]?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email
        case phoneNumber = "phone_number"
        case friendIds = "friend_ids"
        case fcmToken = "fcm_token"
        case createdAt = "created_at"
        case elo
        case deckStats = "deck_stats"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        displayName = try container.decode(String.self, forKey: .displayName)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        friendIds = try container.decodeIfPresent([String].self, forKey: .friendIds) ?? []
        fcmToken = try container.decodeIfPresent(String.self, forKey: .fcmToken)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        elo = try container.decodeIfPresent(Int.self, forKey: .elo) ?? 1500
        deckStats = try container.decodeIfPresent([String: DeckStat].self, forKey: .deckStats)
    }

    init(
        id: String,
        displayName: String,
        email: String?,
        phoneNumber: String?,
        friendIds: [String],
        fcmToken: String? = nil,
        createdAt: Date,
        elo: Int = 1500,
        deckStats: [String: DeckStat]? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.phoneNumber = phoneNumber
        self.friendIds = friendIds
        self.fcmToken = fcmToken
        self.createdAt = createdAt
        self.elo = elo
        self.deckStats = deckStats
    }
}
