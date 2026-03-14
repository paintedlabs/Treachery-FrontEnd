//
//  PreviewHelpers.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

#if DEBUG
import SwiftUI

// MARK: - Sample Players

extension Player {
    static let sampleLeader = Player(
        id: "p1",
        orderId: 0,
        userId: "user1",
        displayName: "Luke",
        role: .leader,
        identityCardId: "L01",
        lifeTotal: 45,
        isEliminated: false,
        isUnveiled: false,
        joinedAt: Date()
    )

    static let sampleGuardian = Player(
        id: "p2",
        orderId: 1,
        userId: "user2",
        displayName: "Sarah",
        role: .guardian,
        identityCardId: "G01",
        lifeTotal: 40,
        isEliminated: false,
        isUnveiled: false,
        joinedAt: Date()
    )

    static let sampleAssassin = Player(
        id: "p3",
        orderId: 2,
        userId: "user3",
        displayName: "Marcus",
        role: .assassin,
        identityCardId: "A01",
        lifeTotal: 32,
        isEliminated: false,
        isUnveiled: true,
        joinedAt: Date()
    )

    static let sampleTraitor = Player(
        id: "p4",
        orderId: 3,
        userId: "user4",
        displayName: "Elena",
        role: .traitor,
        identityCardId: "T01",
        lifeTotal: 40,
        isEliminated: false,
        isUnveiled: false,
        joinedAt: Date()
    )

    static let sampleEliminated = Player(
        id: "p5",
        orderId: 4,
        userId: "user5",
        displayName: "Jin",
        role: .assassin,
        identityCardId: "A02",
        lifeTotal: 0,
        isEliminated: true,
        isUnveiled: true,
        joinedAt: Date()
    )

    static let sampleLobbyPlayers: [Player] = [
        Player(id: "lp1", orderId: 0, userId: "user1", displayName: "Luke", role: nil, identityCardId: nil, lifeTotal: 40, isEliminated: false, isUnveiled: false, joinedAt: Date()),
        Player(id: "lp2", orderId: 1, userId: "user2", displayName: "Sarah", role: nil, identityCardId: nil, lifeTotal: 40, isEliminated: false, isUnveiled: false, joinedAt: Date()),
        Player(id: "lp3", orderId: 2, userId: "user3", displayName: "Marcus", role: nil, identityCardId: nil, lifeTotal: 40, isEliminated: false, isUnveiled: false, joinedAt: Date()),
    ]

    static let sampleGamePlayers: [Player] = [
        .sampleLeader,
        .sampleGuardian,
        .sampleAssassin,
        .sampleTraitor,
        .sampleEliminated,
    ]
}

// MARK: - Sample Identity Card

extension IdentityCard {
    static let sampleLeaderCard = IdentityCard(
        id: "L01",
        cardNumber: 1,
        name: "The Sovereign",
        role: .leader,
        abilityText: "Your life total can't be reduced below 1 as long as you control at least one creature. At the beginning of your upkeep, you gain 2 life.",
        unveilCost: "Pay 3 life",
        rarity: .mythic,
        hasUndercover: false,
        undercoverCondition: nil,
        timingRestriction: nil,
        lifeModifier: 5,
        handSizeModifier: nil,
        flavorText: "A ruler must be willing to sacrifice everything for their people.",
        imageAssetName: nil
    )

    static let sampleGuardianCard = IdentityCard(
        id: "G01",
        cardNumber: 14,
        name: "Shield Bearer",
        role: .guardian,
        abilityText: "Whenever the Leader is dealt damage, you may redirect 2 of that damage to yourself instead.",
        unveilCost: "Pay 5 life",
        rarity: .rare,
        hasUndercover: false,
        undercoverCondition: nil,
        timingRestriction: "Only during combat",
        lifeModifier: nil,
        handSizeModifier: 1,
        flavorText: "The shield is mightier than the sword when protecting those who matter.",
        imageAssetName: nil
    )

    static let sampleAssassinCard = IdentityCard(
        id: "A01",
        cardNumber: 32,
        name: "Shadow Stalker",
        role: .assassin,
        abilityText: "When you unveil, target player loses 5 life. You have hexproof until end of turn.",
        unveilCost: "Sacrifice a creature",
        rarity: .rare,
        hasUndercover: true,
        undercoverCondition: "Control three or more creatures",
        timingRestriction: nil,
        lifeModifier: -3,
        handSizeModifier: nil,
        flavorText: nil,
        imageAssetName: nil
    )

    static let sampleTraitorCard = IdentityCard(
        id: "T01",
        cardNumber: 50,
        name: "Double Agent",
        role: .traitor,
        abilityText: "When you unveil, choose a player. You and that player each draw 3 cards. Then that player discards 3 cards at random.",
        unveilCost: "Pay 7 life",
        rarity: .uncommon,
        hasUndercover: false,
        undercoverCondition: nil,
        timingRestriction: nil,
        lifeModifier: nil,
        handSizeModifier: nil,
        flavorText: "Trust is a currency best spent on yourself.",
        imageAssetName: nil
    )
}

// MARK: - Sample Games

extension Game {
    static let sampleWaiting = Game(
        id: "game1",
        code: "ABCD",
        hostId: "user1",
        state: .waiting,
        maxPlayers: 6,
        startingLife: 40,
        winningTeam: nil,
        playerIds: ["user1", "user2", "user3"],
        createdAt: Date()
    )

    static let sampleInProgress = Game(
        id: "game2",
        code: "EFGH",
        hostId: "user1",
        state: .inProgress,
        maxPlayers: 5,
        startingLife: 40,
        winningTeam: nil,
        playerIds: ["user1", "user2", "user3", "user4", "user5"],
        createdAt: Date()
    )

    static let sampleFinishedLeaderWin = Game(
        id: "game3",
        code: "JKLM",
        hostId: "user1",
        state: .finished,
        maxPlayers: 5,
        startingLife: 40,
        winningTeam: "leader",
        playerIds: ["user1", "user2", "user3", "user4", "user5"],
        createdAt: Date().addingTimeInterval(-86400)
    )

    static let sampleFinishedAssassinWin = Game(
        id: "game4",
        code: "NPQR",
        hostId: "user3",
        state: .finished,
        maxPlayers: 4,
        startingLife: 40,
        winningTeam: "assassin",
        playerIds: ["user1", "user2", "user3", "user4"],
        createdAt: Date().addingTimeInterval(-172800)
    )
}

// MARK: - Sample Users

extension TreacheryUser {
    static let sampleUser = TreacheryUser(
        id: "user1",
        displayName: "Luke",
        email: "luke@example.com",
        phoneNumber: nil,
        friendIds: ["user2", "user3"],
        createdAt: Date().addingTimeInterval(-604800)
    )

    static let sampleFriend1 = TreacheryUser(
        id: "user2",
        displayName: "Sarah",
        email: "sarah@example.com",
        phoneNumber: nil,
        friendIds: ["user1"],
        createdAt: Date().addingTimeInterval(-500000)
    )

    static let sampleFriend2 = TreacheryUser(
        id: "user3",
        displayName: "Marcus",
        email: nil,
        phoneNumber: "+15551234567",
        friendIds: ["user1"],
        createdAt: Date().addingTimeInterval(-300000)
    )
}

// MARK: - Sample Friend Requests

extension FriendRequest {
    static let samplePending = FriendRequest(
        id: "fr1",
        fromUserId: "user4",
        fromDisplayName: "Elena",
        toUserId: "user1",
        status: .pending,
        createdAt: Date().addingTimeInterval(-3600)
    )

    static let samplePending2 = FriendRequest(
        id: "fr2",
        fromUserId: "user5",
        fromDisplayName: "Jin",
        toUserId: "user1",
        status: .pending,
        createdAt: Date().addingTimeInterval(-7200)
    )
}

// MARK: - Preview NavigationPath

extension Binding where Value == NavigationPath {
    /// A constant NavigationPath binding for use in previews.
    static var preview: Binding<NavigationPath> {
        .constant(NavigationPath())
    }
}
#endif
