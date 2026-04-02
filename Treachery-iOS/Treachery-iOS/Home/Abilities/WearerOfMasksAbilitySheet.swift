//
//  WearerOfMasksAbilitySheet.swift
//  Treachery-iOS
//

import SwiftUI

struct WearerOfMasksAbilitySheet: View {
    @ObservedObject var viewModel: GameBoardViewModel
    @Environment(\.dismiss) var dismiss
    @State private var xValue = 3
    @State private var revealedCards: [IdentityCard] = []
    @State private var selectedCardId: String?
    @State private var hasRevealed = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mtgBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        headerSection
                        abilityReminderSection

                        if !hasRevealed {
                            xValueSection
                            revealButton
                        } else {
                            cardSelectionSection
                            actionButtons
                        }
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        Task {
                            await viewModel.resolveWearerOfMasks(chosenCardId: nil)
                        }
                        dismiss()
                    }
                    .foregroundStyle(Color.mtgTextSecondary)
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "theatermasks.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.mtgTraitor)

            Text("The Wearer of Masks")
                .font(.system(.title2, design: .serif))
                .fontWeight(.bold)
                .foregroundStyle(Color.mtgTextPrimary)
        }
    }

    private var abilityReminderSection: some View {
        Text("Reveal up to X non-Leader identity cards at random from outside the game. You may choose one to become a copy of, except it's a Traitor.")
            .font(.caption)
            .foregroundStyle(Color.mtgTextSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }

    private var xValueSection: some View {
        VStack(spacing: 12) {
            Text("How much mana did you pay for X?")
                .font(.subheadline)
                .foregroundStyle(Color.mtgTextPrimary)

            HStack(spacing: 20) {
                Button {
                    if xValue > 1 { xValue -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.mtgAssassin)
                }
                .buttonStyle(.plain)

                Text("\(xValue)")
                    .font(.system(size: 48, weight: .bold, design: .serif))
                    .foregroundStyle(Color.mtgGold)
                    .frame(minWidth: 60)

                Button {
                    xValue += 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.mtgSuccess)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color.mtgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.mtgDivider, lineWidth: 1)
        )
    }

    private var revealButton: some View {
        Button {
            let available = viewModel.cardsOutsideGame()
            let count = min(xValue, available.count)
            revealedCards = Array(available.shuffled().prefix(count))
            withAnimation { hasRevealed = true }
        } label: {
            Text("Reveal Cards")
                .fontWeight(.semibold)
        }
        .buttonStyle(MtgPrimaryButtonStyle())
    }

    private var cardSelectionSection: some View {
        VStack(spacing: 12) {
            Text("Choose an Identity")
                .font(.headline)
                .foregroundStyle(Color.mtgGold)

            if revealedCards.isEmpty {
                Text("No eligible cards outside the game.")
                    .font(.subheadline)
                    .foregroundStyle(Color.mtgTextSecondary)
                    .padding()
            } else {
                ForEach(revealedCards) { card in
                    cardRow(card)
                }
            }
        }
    }

    private func cardRow(_ card: IdentityCard) -> some View {
        let isSelected = selectedCardId == card.id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCardId = isSelected ? nil : card.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Circle()
                        .fill(card.role.color)
                        .frame(width: 10, height: 10)
                    Text(card.name)
                        .font(.system(.subheadline, design: .serif))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.mtgTextPrimary)
                    Spacer()
                    Text(card.role.displayName)
                        .font(.caption)
                        .foregroundStyle(card.role.color)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.mtgGold)
                    }
                }

                Text(card.abilityText)
                    .font(.caption)
                    .foregroundStyle(Color.mtgTextSecondary)
                    .lineLimit(3)
            }
            .padding(12)
            .background(isSelected ? Color.mtgTraitor.opacity(0.15) : Color.mtgSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.mtgTraitor : Color.mtgDivider, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if selectedCardId != nil {
                Button {
                    Task {
                        await viewModel.resolveWearerOfMasks(chosenCardId: selectedCardId)
                    }
                    dismiss()
                } label: {
                    Text("Become This Identity")
                        .fontWeight(.semibold)
                }
                .buttonStyle(MtgPrimaryButtonStyle())
            }

            Button {
                Task {
                    await viewModel.resolveWearerOfMasks(chosenCardId: nil)
                }
                dismiss()
            } label: {
                Text("Decline")
                    .fontWeight(.medium)
            }
            .buttonStyle(MtgSecondaryButtonStyle())
        }
    }
}

#if DEBUG
#Preview("Wearer of Masks") {
    let vm = GameBoardViewModel(
        gameId: "preview",
        previewPlayers: Player.sampleGamePlayers,
        previewGame: .sampleInProgress,
        currentUserId: "user4"
    )
    WearerOfMasksAbilitySheet(viewModel: vm)
}
#endif
