//
//  IdentityCardView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import SwiftUI

/// Full-screen MTG-styled identity card detail view.
/// Tap the card header in GameBoardView to present this as a sheet.
struct IdentityCardView: View {
    let card: IdentityCard
    let player: Player
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mtgBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Card frame
                        VStack(spacing: 0) {
                            // Title bar
                            HStack {
                                Text(card.name)
                                    .font(.system(.headline, design: .serif))
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.mtgTextPrimary)
                                Spacer()
                                Text("#\(card.cardNumber)")
                                    .font(.caption)
                                    .foregroundStyle(Color.mtgTextSecondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.mtgCardElevated)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(card.name), card number \(card.cardNumber)")

                            Rectangle()
                                .fill(Color.mtgDivider)
                                .frame(height: 1)

                            // Role & Rarity bar
                            HStack {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(player.role?.color ?? .gray)
                                        .frame(width: 10, height: 10)
                                    Text(player.role?.displayName ?? "Unknown")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(player.role?.color ?? Color.mtgTextPrimary)
                                }
                                Spacer()
                                Text(card.rarity.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(rarityColor)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Role: \(player.role?.displayName ?? "Unknown"), Rarity: \(card.rarity.displayName)")

                            Rectangle()
                                .fill(Color.mtgDivider)
                                .frame(height: 1)

                            // Ability text
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Ability")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.mtgGold)

                                Text(card.abilityText)
                                    .font(.body)
                                    .foregroundStyle(Color.mtgTextPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Ability: \(card.abilityText)")

                            Rectangle()
                                .fill(Color.mtgDivider)
                                .frame(height: 1)

                            // Unveil cost
                            HStack {
                                Image(systemName: "eye.fill")
                                    .foregroundStyle(player.role?.color ?? Color.mtgGold)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Unveil Cost")
                                        .font(.caption)
                                        .foregroundStyle(Color.mtgTextSecondary)
                                    Text(card.unveilCost)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.mtgTextPrimary)
                                }
                                Spacer()
                                if player.isUnveiled {
                                    Text("UNVEILED")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(Color.mtgBackground)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(player.role?.color ?? .gray)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(16)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Unveil cost: \(card.unveilCost)\(player.isUnveiled ? ", currently unveiled" : "")")

                            // Undercover condition
                            if card.hasUndercover, let condition = card.undercoverCondition {
                                Rectangle()
                                    .fill(Color.mtgDivider)
                                    .frame(height: 1)
                                HStack(alignment: .top) {
                                    Image(systemName: "theatermasks.fill")
                                        .foregroundStyle(Color.mtgTraitor)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Undercover")
                                            .font(.caption)
                                            .foregroundStyle(Color.mtgTextSecondary)
                                        Text(condition)
                                            .font(.subheadline)
                                            .foregroundStyle(Color.mtgTextPrimary)
                                    }
                                    Spacer()
                                }
                                .padding(16)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Undercover condition: \(condition)")
                            }

                            // Timing restriction
                            if let timing = card.timingRestriction {
                                Rectangle()
                                    .fill(Color.mtgDivider)
                                    .frame(height: 1)
                                HStack(alignment: .top) {
                                    Image(systemName: "clock.fill")
                                        .foregroundStyle(Color.mtgGold)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Timing")
                                            .font(.caption)
                                            .foregroundStyle(Color.mtgTextSecondary)
                                        Text(timing)
                                            .font(.subheadline)
                                            .foregroundStyle(Color.mtgTextPrimary)
                                    }
                                    Spacer()
                                }
                                .padding(16)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Timing restriction: \(timing)")
                            }

                            // Modifiers
                            if card.lifeModifier != nil || card.handSizeModifier != nil {
                                Rectangle()
                                    .fill(Color.mtgDivider)
                                    .frame(height: 1)
                                HStack(spacing: 24) {
                                    if let life = card.lifeModifier {
                                        HStack(spacing: 4) {
                                            Image(systemName: "heart.fill")
                                                .foregroundStyle(Color.mtgError)
                                            Text(life >= 0 ? "+\(life)" : "\(life)")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(Color.mtgTextPrimary)
                                            Text("Life")
                                                .font(.caption)
                                                .foregroundStyle(Color.mtgTextSecondary)
                                        }
                                        .accessibilityElement(children: .combine)
                                        .accessibilityLabel("Life modifier: \(life >= 0 ? "plus" : "minus") \(abs(life))")
                                    }
                                    if let hand = card.handSizeModifier {
                                        HStack(spacing: 4) {
                                            Image(systemName: "hand.raised.fill")
                                                .foregroundStyle(Color.mtgGuardian)
                                            Text(hand >= 0 ? "+\(hand)" : "\(hand)")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(Color.mtgTextPrimary)
                                            Text("Hand Size")
                                                .font(.caption)
                                                .foregroundStyle(Color.mtgTextSecondary)
                                        }
                                        .accessibilityElement(children: .combine)
                                        .accessibilityLabel("Hand size modifier: \(hand >= 0 ? "plus" : "minus") \(abs(hand))")
                                    }
                                    Spacer()
                                }
                                .padding(16)
                            }

                            // Flavor text
                            if let flavor = card.flavorText, !flavor.isEmpty {
                                Rectangle()
                                    .fill(Color.mtgDivider)
                                    .frame(height: 1)
                                Text(flavor)
                                    .font(.caption)
                                    .italic()
                                    .foregroundStyle(Color.mtgTextSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                                    .accessibilityLabel("Flavor text: \(flavor)")
                            }
                        }
                        .background(Color.mtgSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(player.role?.color ?? Color.mtgBorderAccent, lineWidth: 2)
                        )
                        .padding()

                        // Win condition
                        VStack(spacing: 4) {
                            Text("Win Condition")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.mtgGold)
                            Text(player.role?.winConditionText ?? "")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Color.mtgTextSecondary)
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Win condition: \(player.role?.winConditionText ?? "")")
                    }
                }
            }
            .navigationTitle("Identity Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.mtgGold)
                    .accessibilityLabel("Close identity card")
                }
            }
        }
    }

    private var rarityColor: Color {
        switch card.rarity {
        case .uncommon: return Color.mtgSuccess
        case .rare:     return Color.mtgGuardian
        case .mythic:   return Color.mtgGold
        case .special:  return Color.mtgTraitor
        }
    }
}

#if DEBUG
#Preview("Leader Card - Mythic") {
    IdentityCardView(
        card: .sampleLeaderCard,
        player: .sampleLeader
    )
}

#Preview("Guardian Card - Unveiled") {
    IdentityCardView(
        card: .sampleGuardianCard,
        player: Player(
            id: "p2", orderId: 1, userId: "user2",
            displayName: "Sarah", role: .guardian,
            identityCardId: "G01", lifeTotal: 40,
            isEliminated: false, isUnveiled: true,
            joinedAt: Date()
        )
    )
}

#Preview("Assassin Card - With Undercover") {
    IdentityCardView(
        card: .sampleAssassinCard,
        player: .sampleAssassin
    )
}

#Preview("Traitor Card") {
    IdentityCardView(
        card: .sampleTraitorCard,
        player: .sampleTraitor
    )
}
#endif
