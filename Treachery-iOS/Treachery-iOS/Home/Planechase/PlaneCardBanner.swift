//
//  PlaneCardBanner.swift
//  Treachery-iOS
//

import SwiftUI

/// Compact bar showing the current plane name and type, tappable to open a detail sheet.
/// When `secondaryPlane` is provided (e.g., Spatial Merging), both planes are shown stacked.
struct PlaneCardBanner: View {
    let plane: PlaneCard
    var secondaryPlane: PlaneCard? = nil
    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: plane.isPhenomenon ? "sparkles" : "globe")
                    .font(.title3)
                    .foregroundStyle(Color.mtgGold)

                VStack(alignment: .leading, spacing: 2) {
                    Text(plane.name)
                        .font(.system(.subheadline, design: .serif))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.mtgTextPrimary)
                        .lineLimit(1)

                    if let secondary = secondaryPlane {
                        HStack(spacing: 6) {
                            Text("+")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.mtgGold)
                            Text(secondary.name)
                                .font(.system(.subheadline, design: .serif))
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.mtgTextPrimary)
                                .lineLimit(1)
                        }
                    }

                    Text(plane.typeLine)
                        .font(.caption2)
                        .foregroundStyle(Color.mtgTextSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.mtgTextSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.mtgSurface)
            .overlay(
                Rectangle()
                    .fill(Color.mtgBorderAccent)
                    .frame(height: 1),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Current plane: \(plane.name)")
        .accessibilityHint("Tap to view plane details")
        .sheet(isPresented: $showDetail) {
            PlaneCardDetailView(plane: plane)
        }
    }
}
