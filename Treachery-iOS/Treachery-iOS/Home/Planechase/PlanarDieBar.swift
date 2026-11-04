//
//  PlanarDieBar.swift
//  Treachery-iOS
//

import SwiftUI

/// Bottom bar with a "Roll Planar Die" button, mana cost display, die result animation,
/// and last roller info.
struct PlanarDieBar: View {
    @ObservedObject var viewModel: GameBoardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            // Die result display
            if let result = viewModel.dieRollResult {
                dieResultView(result: result)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }

            // The cost sits beside the button, or under it on one line when
            // the text is too large for both side by side.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    rollButton
                    manaCost(onOneLine: false)
                }
                VStack(spacing: 8) {
                    rollButton
                    manaCost(onOneLine: true)
                }
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
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.7), value: viewModel.dieRollResult)
    }

    private var rollButton: some View {
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
                    .fill(canTapRoll ? Color.mtgGold : Color.mtgGold.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
        .disabled(!canTapRoll)
        .accessibilityLabel("Roll planar die")
    }

    /// The next roll's cost: the number over "Mana", or the two on one line.
    /// VoiceOver reads it as one sentence.
    private func manaCost(onOneLine: Bool) -> some View {
        let layout = onOneLine
            ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
            : AnyLayout(VStackLayout(spacing: 2))
        return layout {
            Text("\(viewModel.dieRollCost)")
                .font(.system(.title2, design: .serif))
                .fontWeight(.bold)
                .foregroundStyle(viewModel.dieRollCost > 0 ? Color.mtgGold : Color.mtgTextSecondary)
            Text("Mana")
                .font(.caption2)
                .foregroundStyle(Color.mtgTextSecondary)
        }
        .frame(minWidth: 50)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your next roll costs \(viewModel.dieRollCost) mana")
    }

    /// Spectators can't roll, and nobody can while a roll is under way.
    /// The view model refuses those rolls as well; this keeps the button
    /// from looking tappable.
    private var canTapRoll: Bool {
        viewModel.canRollDie && !viewModel.isRollingDie
    }

    @ViewBuilder
    private func dieResultView(result: String) -> some View {
        HStack(spacing: 10) {
            dieIcon(for: result)
                .font(.title)
                .foregroundStyle(dieColor(for: result))
                // A value that never changes never bounces.
                .symbolEffect(.bounce, value: reduceMotion ? nil : result)

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
        .accessibilityElement(children: .ignore)
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
