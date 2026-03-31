//
//  PlaneCardDetailView.swift
//  Treachery-iOS
//

import SwiftUI

/// Full detail sheet for a plane card with image, name, type line, and oracle text.
struct PlaneCardDetailView: View {
    let plane: PlaneCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color.mtgTextSecondary)
                        }
                    }
                    .padding(.horizontal)

                    // Card image
                    if let imageUri = plane.imageUri, let url = URL(string: imageUri) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            case .failure:
                                imagePlaceholder(icon: "photo.badge.exclamationmark")
                            case .empty:
                                imagePlaceholder(icon: "photo")
                                    .overlay(ProgressView().tint(Color.mtgGold))
                            @unknown default:
                                imagePlaceholder(icon: "photo")
                            }
                        }
                        .frame(maxHeight: 340)
                        .padding(.horizontal)
                    }

                    // Card info
                    VStack(alignment: .leading, spacing: 12) {
                        Text(plane.name)
                            .font(.system(.title2, design: .serif))
                            .fontWeight(.bold)
                            .foregroundStyle(Color.mtgTextPrimary)

                        Text(plane.typeLine)
                            .font(.subheadline)
                            .foregroundStyle(Color.mtgGold)

                        if plane.isPhenomenon {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                Text("PHENOMENON")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .kerning(1.2)
                            }
                            .foregroundStyle(Color.mtgGoldBright)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.mtgGoldBright.opacity(0.15))
                            .clipShape(Capsule())
                        }

                        Rectangle()
                            .fill(Color.mtgDivider)
                            .frame(height: 1)

                        Text(plane.oracleText)
                            .font(.body)
                            .foregroundStyle(Color.mtgTextPrimary)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 40)
                }
                .padding(.top)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func imagePlaceholder(icon: String) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.mtgCardElevated)
            .frame(height: 240)
            .overlay(
                Image(systemName: icon)
                    .font(.largeTitle)
                    .foregroundStyle(Color.mtgTextSecondary)
            )
    }
}
