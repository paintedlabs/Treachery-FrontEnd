//
//  PhenomenonOverlay.swift
//  Treachery-iOS
//

import SwiftUI

/// Shown when the current plane is a phenomenon, with a "Resolve" button.
struct PhenomenonOverlay: View {
    let plane: PlaneCard
    @ObservedObject var viewModel: GameBoardViewModel

    var body: some View {
        VStack(spacing: 16) {
            // Phenomenon indicator
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Color.mtgGoldBright)
                Text("PHENOMENON")
                    .font(.system(.headline, design: .serif))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.mtgGoldBright)
                    .kerning(1.5)
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Color.mtgGoldBright)
            }

            Text(plane.name)
                .font(.system(.title3, design: .serif))
                .fontWeight(.semibold)
                .foregroundStyle(Color.mtgTextPrimary)

            Text(plane.oracleText)
                .font(.subheadline)
                .foregroundStyle(Color.mtgTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal)

            Button {
                Task { await viewModel.resolvePhenomenon() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isPending {
                        ProgressView()
                            .tint(Color.mtgBackground)
                            .controlSize(.small)
                    }
                    Text("Resolve Phenomenon")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(MtgPrimaryButtonStyle(isDisabled: viewModel.isPending))
            .disabled(viewModel.isPending)
            .padding(.horizontal, 40)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            Color.mtgSurface
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(Color.mtgGoldBright, lineWidth: 1)
                )
        )
        .overlay(
            // Top glow effect
            LinearGradient(
                colors: [Color.mtgGoldBright.opacity(0.2), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 4),
            alignment: .top
        )
    }
}
