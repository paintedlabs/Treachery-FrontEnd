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
    let email: String?
    var phoneNumber: String?
    var friendIds: [String]
    var fcmToken: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email
        case phoneNumber = "phone_number"
        case friendIds = "friend_ids"
        case fcmToken = "fcm_token"
        case createdAt = "created_at"
    }
}
