//
//  PlaneCard.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/16/26.
//

import Foundation

struct PlaneCard: Codable, Identifiable {
    let id: String
    let name: String
    let typeLine: String
    let oracleText: String
    let imageUri: String?
    let isPhenomenon: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case typeLine = "type_line"
        case oracleText = "oracle_text"
        case imageUri = "image_uri"
        case isPhenomenon = "is_phenomenon"
    }
}
