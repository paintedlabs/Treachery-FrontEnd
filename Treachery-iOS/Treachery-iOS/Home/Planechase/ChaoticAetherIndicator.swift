//
//  ChaoticAetherIndicator.swift
//  Treachery-iOS
//

import SwiftUI

/// Small banner indicating that Chaotic Aether is active — blank die rolls become chaos.
struct ChaoticAetherIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.caption)
                .foregroundStyle(Color.mtgGoldBright)

            Text("Chaotic Aether Active — Blanks become Chaos")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.mtgGoldBright)

            Image(systemName: "bolt.fill")
                .font(.caption)
                .foregroundStyle(Color.mtgGoldBright)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.mtgGoldBright.opacity(0.12))
        .overlay(
            Rectangle()
                .fill(Color.mtgGoldBright.opacity(0.4))
                .frame(height: 1),
            alignment: .bottom
        )
        .accessibilityLabel("Chaotic Aether is active. Blank die rolls count as chaos.")
    }
}
