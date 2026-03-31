//
//  PlanarDieBar.swift
//  Treachery-iOS
//

import SwiftUI

/// Bottom bar with a "Roll Planar Die" button, mana cost display, die result animation,
/// and last roller info.
struct PlanarDieBar: View {
    @ObservedObject var viewModel: GameBoardViewModel

    var body: some View {
        VStack(spacing: 8) {
            // Die result display
            if let result = viewModel.dieRollResult {
                dieResultView(result: result)
                    .transition(.scale.combined(with: .opacity))
            }

            HStack(spacing: 16) {
                // Roll button
                Button {
                    Task { await viewModel.rollDie() }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isRollingDie {
                            ProgressView()
                                .tint(Color.mtgBackground)
                                .controlSize(.small)
                        } else {
                            Image(systemName: "dice.fill")
                                .font(.body)
                        }
                        Text("Roll Planar Die")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Color.mtgBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(viewModel.isRollingDie ? Color.mtgGold.opacity(0.4) : Color.mtgGold)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isRollingDie)
                .accessibilityLabel("Roll planar die")

                // Mana cost indicator
                VStack(spacing: 2) {
                    Text("\(viewModel.dieRollCost)")
                        .font(.system(.title2, design: .serif))
                        .fontWeight(.bold)
                        .foregroundStyle(viewModel.dieRollCost > 0 ? Color.mtgGold : Color.mtgTextSecondary)
                    Text("Mana")
                        .font(.caption2)
                        .foregroundStyle(Color.mtgTextSecondary)
                }
                .frame(width: 50)
                .accessibilityLabel("Roll cost: \(viewModel.dieRollCost) mana")
            }

            // Last roller info
            if let rollerName = viewModel.lastDieRollerName {
                Text("Last roll by \(rollerName)")
                    .font(.caption2)
                    .foregroundStyle(Color.mtgTextSecondary)
                    .italic()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.mtgSurface)
        .overlay(
            Rectangle()
                .fill(Color.mtgDivider)
                .frame(height: 1),
            alignment: .top
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.dieRollResult)
    }

    @ViewBuilder
    private func dieResultView(result: String) -> some View {
        HStack(spacing: 10) {
            dieIcon(for: result)
                .font(.title)
                .foregroundStyle(dieColor(for: result))
                .symbolEffect(.bounce, value: result)

            Text(dieLabel(for: result))
                .font(.system(.headline, design: .serif))
                .fontWeight(.bold)
                .foregroundStyle(dieColor(for: result))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(dieColor(for: result).opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(dieColor(for: result).opacity(0.3), lineWidth: 1)
                )
        )
        .accessibilityLabel("Die result: \(dieLabel(for: result))")
    }

    private func dieIcon(for result: String) -> Image {
        switch result {
        case "chaos":
            return Image(systemName: "bolt.fill")
        case "planeswalk":
            return Image(systemName: "arrow.right.circle.fill")
        default:
            return Image(systemName: "circle")
        }
    }

    private func dieColor(for result: String) -> Color {
        switch result {
        case "chaos":
            return Color.mtgAssassin
        case "planeswalk":
            return Color.mtgGuardian
        default:
            return Color.mtgTextSecondary
        }
    }

    private func dieLabel(for result: String) -> String {
        switch result {
        case "chaos":
            return "Chaos!"
        case "planeswalk":
            return "Planeswalk!"
        default:
            return "Blank"
        }
    }
}
