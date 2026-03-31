//
//  LobbyGameCodeCard.swift
//  Treachery-iOS
//

import SwiftUI

struct LobbyGameCodeCard: View {
    let game: Game
    @Binding var showShareSheet: Bool

    var body: some View {
        VStack(spacing: 10) {
            MtgSectionHeader(title: "Game Code")

            Text(game.code)
                .font(.system(size: 52, weight: .bold, design: .monospaced))
                .mtgGoldShimmer()
                .kerning(10)
                .shadow(color: Color.mtgGold.opacity(0.3), radius: 12, x: 0, y: 0)
                .accessibilityLabel("Game code: \(game.code.map(String.init).joined(separator: " "))")

            Text(game.gameMode.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.mtgBackground)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "e4c96a"), Color(hex: "c9a84c")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .accessibilityLabel("Game mode: \(game.gameMode.displayName)")

            HStack(spacing: 16) {
                Button {
                    UIPasteboard.general.string = game.code
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                        Text("Copy")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.mtgGold)
                }
                .accessibilityLabel("Copy game code")

                Button {
                    showShareSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption)
                        Text("Share")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.mtgGold)
                }
                .accessibilityLabel("Share game code with friends")
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .mtgCardFrame()
        .mtgCardGlow(color: .mtgGold, radius: 12, opacity: 0.12)
        .padding(.horizontal)
        .padding(.top, 12)
    }
}
