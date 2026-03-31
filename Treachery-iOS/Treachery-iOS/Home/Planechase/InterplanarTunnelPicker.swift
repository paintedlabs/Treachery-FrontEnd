//
//  InterplanarTunnelPicker.swift
//  Treachery-iOS
//

import SwiftUI

/// Overlay shown when resolving Interplanar Tunnel — the player picks one of five revealed planes.
struct InterplanarTunnelPicker: View {
    let options: [PlaneCard]
    @ObservedObject var viewModel: GameBoardViewModel

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            VStack(spacing: 16) {
                // Header
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.title2)
                            .foregroundStyle(Color.mtgGold)
                        Text("Interplanar Tunnel")
                            .font(.system(.title2, design: .serif))
                            .fontWeight(.bold)
                            .foregroundStyle(Color.mtgTextPrimary)
                    }

                    Text("Choose your next destination")
                        .font(.subheadline)
                        .foregroundStyle(Color.mtgTextSecondary)
                }
                .padding(.top, 24)

                Rectangle()
                    .fill(Color.mtgDivider)
                    .frame(height: 1)
                    .padding(.horizontal)

                // Plane options list
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(options) { plane in
                            Button {
                                Task { await viewModel.selectTunnelPlane(plane) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "globe")
                                        .font(.title3)
                                        .foregroundStyle(Color.mtgGold)
                                        .frame(width: 32)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(plane.name)
                                            .font(.system(.body, design: .serif))
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Color.mtgTextPrimary)
                                            .lineLimit(1)

                                        Text(plane.typeLine)
                                            .font(.caption)
                                            .foregroundStyle(Color.mtgTextSecondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(Color.mtgTextSecondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.mtgSurface)
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isPending)
                            .accessibilityLabel("Select \(plane.name)")

                            if plane.id != options.last?.id {
                                Rectangle()
                                    .fill(Color.mtgDivider)
                                    .frame(height: 1)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.mtgBorderAccent, lineWidth: 1)
                    )
                    .padding(.horizontal)
                }

                // Loading indicator
                if viewModel.isPending {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(Color.mtgGold)
                            .controlSize(.small)
                        Text("Traveling...")
                            .font(.subheadline)
                            .foregroundStyle(Color.mtgTextSecondary)
                    }
                    .padding(.bottom, 16)
                }

                Spacer(minLength: 20)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
