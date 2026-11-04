//
//  GameBoardIdentityArea.swift
//  Treachery-iOS
//

import SwiftUI

/// The top of the board: the signed-in user's identity card, or why there's
/// none. A user without a seat gets this in every mode: it's their way home.
struct GameBoardIdentityArea: View {
    @ObservedObject var viewModel: GameBoardViewModel
    let onShowCard: () -> Void
    let onGoHome: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch viewModel.identityArea {
        case .notDealt:
            EmptyView()
        case .card(let card, let player):
            ZStack {
                Button {
                    onShowCard()
                } label: {
                    IdentityCardHeader(card: card, player: player)
                }
                .buttonStyle(.plain)
                // The header turns edge-on, then back face-up. With Reduce
                // Motion it fades out and back in instead.
                .rotation3DEffect(
                    .degrees(!reduceMotion && viewModel.unveilProgress == .flippingAway ? 90 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )
                .opacity(reduceMotion && viewModel.unveilProgress == .flippingAway ? 0 : 1)
                .animation(
                    viewModel.unveilProgress == .flippingAway ? .easeIn(duration: 0.3) : .easeOut(duration: 0.3),
                    value: viewModel.unveilProgress
                )

                // Unveiled banner overlay, once the server has
                // unveiled the player
                if viewModel.unveilProgress == .revealing {
                    VStack {
                        Text("IDENTITY REVEALED")
                            .font(.headline)
                            .fontWeight(.black)
                            .foregroundStyle(Color.mtgBackground)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(player.role?.color ?? Color.mtgGuardian)
                                    .shadow(color: (player.role?.color ?? Color.mtgGuardian).opacity(0.6), radius: 12)
                            )
                    }
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    .zIndex(1)
                }
            }
            .animation(
                viewModel.unveilProgress == .revealing && !reduceMotion
                    ? .spring(response: 0.4, dampingFraction: 0.6)
                    : .easeOut(duration: 0.5),
                value: viewModel.unveilProgress
            )
        case .taken:
            VStack(spacing: 8) {
                Image(systemName: "theatermasks.fill")
                    .font(.title)
                    .foregroundStyle(Color.mtgGold)
                    .accessibilityHidden(true)
                Text("The Metamorph took your identity card.")
                    .font(.subheadline)
                    .foregroundStyle(Color.mtgTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        case .notFound:
            // No seat, or a card this build doesn't know. Without a seat
            // there's no Forfeit, spectator bar or action bar, so this
            // offers its own way out.
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(Color.mtgGold)
                    .accessibilityHidden(true)
                Text("Unable to find your player data")
                    .font(.subheadline)
                    .foregroundStyle(Color.mtgTextSecondary)
                Button {
                    onGoHome()
                } label: {
                    Text("Back to Home")
                        .font(.subheadline)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(Color.mtgGold)
            }
            .padding()
        }
    }
}
