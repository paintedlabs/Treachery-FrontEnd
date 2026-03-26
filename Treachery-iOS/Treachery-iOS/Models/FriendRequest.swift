//
//  FriendRequest.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import Foundation

struct FriendRequest: Codable, Identifiable {
    var id: String
    let fromUserId: String
    let fromDisplayName: String
    let toUserId: String
    let status: FriendRequestStatus
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case fromUserId = "from_user_id"
        case fromDisplayName = "from_display_name"
        case toUserId = "to_user_id"
        case status
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        fromUserId = try container.decode(String.self, forKey: .fromUserId)
        fromDisplayName = try container.decode(String.self, forKey: .fromDisplayName)
        toUserId = try container.decode(String.self, forKey: .toUserId)
        status = try container.decode(FriendRequestStatus.self, forKey: .status)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    init(
        id: String,
        fromUserId: String,
        fromDisplayName: String,
        toUserId: String,
        status: FriendRequestStatus,
        createdAt: Date
    ) {
        self.id = id
        self.fromUserId = fromUserId
        self.fromDisplayName = fromDisplayName
        self.toUserId = toUserId
        self.status = status
        self.createdAt = createdAt
    }
}

enum FriendRequestStatus: String, Codable {
    case pending
    case accepted
    case declined
}
