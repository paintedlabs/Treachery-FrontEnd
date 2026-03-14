//
//  FriendRequest.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import Foundation

struct FriendRequest: Codable, Identifiable {
    let id: String
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
}

enum FriendRequestStatus: String, Codable {
    case pending
    case accepted
    case declined
}
