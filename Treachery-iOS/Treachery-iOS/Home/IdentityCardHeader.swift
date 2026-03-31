//
//  IdentityCardHeader.swift
//  Treachery-iOS
//

import SwiftUI

struct IdentityCardHeader: View {
    let card: IdentityCard
    let player: Player

    /// Leaders are always face-up; unveiled players show openly; everyone else is hidden.
    private var isAlwaysVisible: Bool {
        player.isUnveiled || player.role == .leader
    }

    var body: some View {
        if isAlwaysVisible {
            revealedContent
        } else {
            concealedContent
        }
    }

    // MARK: - Concealed (tap to open sheet)

    private var concealedContent: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "eye.slash.fill")
                    .font(.title3)
                    .foregroundStyle(Color.mtgGold)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(Color.mtgError)
                    Text("\(player.lifeTotal)")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(Color.mtgTextPrimary)
                        .contentTransition(.numericText())
                }
            }

            Text("Tap to peek at your identity")
                .font(.subheadline)
                .foregroundStyle(Color.mtgTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color.mtgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.mtgBorderAccent, lineWidth: 1)
        )
    }

    // MARK: - Revealed (unveiled)

    private var revealedContent: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(player.role?.color ?? .gray)
                        .frame(width: 12, height: 12)
                        .shadow(color: (player.role?.color ?? .gray).opacity(0.5), radius: 4)
                    Text(player.role?.displayName ?? "Unknown")
                        .font(.headline)
                        .foregroundStyle(player.role?.color ?? Color.mtgTextPrimary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(Color.mtgError)
                    Text("\(player.lifeTotal)")
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundStyle(Color.mtgTextPrimary)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: player.lifeTotal)
                }
            }

            HStack {
                Text(card.name)
                    .font(.system(.title3, design: .serif))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.mtgTextPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.mtgTextSecondary)
            }

            Text(card.abilityText)
                .font(.caption)
                .foregroundStyle(Color.mtgTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)

            HStack {
                if player.isUnveiled {
                    MtgBadge(text: "UNVEILED", foregroundColor: .mtgBackground, backgroundColor: player.role?.color ?? .gray)
                } else if player.role == .leader {
                    MtgBadge(text: "LEADER — ALWAYS VISIBLE", foregroundColor: .mtgGold, backgroundColor: Color.mtgGold.opacity(0.15))
                }
                Spacer()
                Text("Tap for details")
                    .font(.caption2)
                    .foregroundStyle(Color.mtgTextSecondary)
            }
        }
        .padding()
        .background(
            ZStack {
                Color.mtgSurface
                LinearGradient(
                    colors: [
                        (player.role?.color ?? Color.mtgGold).opacity(0.1),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(player.role?.color ?? Color.mtgBorderAccent, lineWidth: 1)
        )
    }
}

#if DEBUG
#Preview("Leader (always visible)") {
    IdentityCardHeader(
        card: .sampleLeaderCard,
        player: .sampleLeader
    )
}

#Preview("Hidden (tap to peek)") {
    IdentityCardHeader(
        card: .sampleGuardianCard,
        player: .sampleGuardian
    )
}

#Preview("Unveiled") {
    IdentityCardHeader(
        card: .sampleAssassinCard,
        player: .sampleAssassin
    )
}
#endif
