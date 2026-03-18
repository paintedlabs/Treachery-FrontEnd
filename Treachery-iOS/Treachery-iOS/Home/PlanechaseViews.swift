//
//  PlanechaseViews.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/16/26.
//

import SwiftUI

// MARK: - Plane Card Banner

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

// MARK: - Plane Card Detail View

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

// MARK: - Planar Die Bar

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

// MARK: - Phenomenon Overlay

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

// MARK: - Interplanar Tunnel Picker

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

// MARK: - Chaotic Aether Indicator

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
