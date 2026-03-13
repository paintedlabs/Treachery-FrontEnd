//
//  TreacheryUser.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import Foundation

struct TreacheryUser: Codable, Identifiable {
    let id: String
    var displayName: String
    let email: String
    var friendIds: [String]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email
        case friendIds = "friend_ids"
        case createdAt = "created_at"
    }
}
