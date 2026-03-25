//
//  Theme.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/15/26.
//

import SwiftUI

// MARK: - MTG Color Palette

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }

    // Core backgrounds
    static let mtgBackground = Color(hex: "0d0b1a")
    static let mtgSurface = Color(hex: "1a1528")
    static let mtgCardElevated = Color(hex: "231d35")

    // Accent colors
    static let mtgGold = Color(hex: "c9a84c")
    static let mtgGoldBright = Color(hex: "e4c96a")

    // Text colors
    static let mtgTextPrimary = Color(hex: "ede6d6")
    static let mtgTextSecondary = Color(hex: "8b8698")

    // Divider & border
    static let mtgDivider = Color(hex: "2a2340")
    static let mtgBorderAccent = Color(hex: "c9a84c")

    // Semantic colors
    static let mtgError = Color(hex: "c43c3c")
    static let mtgSuccess = Color(hex: "3ca85c")

    // Role colors
    static let mtgLeader = Color(hex: "e4c96a")
    static let mtgGuardian = Color(hex: "4c8cc9")
    static let mtgAssassin = Color(hex: "c94c4c")
    static let mtgTraitor = Color(hex: "9c4cc9")
}

// MARK: - View Modifiers

/// Dark arcane background applied to a full screen
struct MtgBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.mtgBackground.ignoresSafeArea())
    }
}

/// Radial gradient background — lighter purple center fading to dark edges
struct MtgRadialBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Color.mtgBackground
                    RadialGradient(
                        colors: [
                            Color(hex: "1e1735").opacity(0.8),
                            Color.mtgBackground
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: UIScreen.main.bounds.height * 0.6
                    )
                }
                .ignoresSafeArea()
            )
    }
}

/// Inner glow/shadow for cards to add depth
struct MtgCardGlow: ViewModifier {
    var color: Color = .mtgGold
    var radius: CGFloat = 8
    var opacity: Double = 0.15

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(opacity), radius: radius, x: 0, y: 2)
            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 4)
    }
}

/// Shimmer / metallic gradient for gold text
struct MtgGoldShimmer: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(hex: "c9a84c"),
                        Color(hex: "f0d878"),
                        Color(hex: "e4c96a"),
                        Color(hex: "c9a84c"),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

/// Card-frame style container with gold border and subtle depth shadow
struct MtgCardFrame: ViewModifier {
    var borderColor: Color = .mtgBorderAccent

    func body(content: Content) -> some View {
        content
            .background(Color.mtgSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .shadow(color: borderColor.opacity(0.1), radius: 8, x: 0, y: 2)
            .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 4)
    }
}

/// Gold-accented primary button style with scale animation
struct MtgPrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(Color.mtgBackground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isDisabled
                            ? AnyShapeStyle(Color.mtgGold.opacity(0.4))
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color(hex: "e4c96a"), Color(hex: "c9a84c"), Color(hex: "b8942f")],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            )
            .shadow(color: isDisabled ? .clear : Color.mtgGold.opacity(0.3), radius: 6, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Gold-bordered secondary button style with scale animation
struct MtgSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .foregroundStyle(Color.mtgGold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.mtgGold.opacity(configuration.isPressed ? 0.08 : 0.03))
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.mtgGold, lineWidth: 1.5)
                }
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    /// Apply the dark arcane background
    func mtgBackground() -> some View {
        modifier(MtgBackgroundModifier())
    }

    /// Apply the radial gradient background
    func mtgRadialBackground() -> some View {
        modifier(MtgRadialBackgroundModifier())
    }

    /// Apply a card-frame style
    func mtgCardFrame(borderColor: Color = .mtgBorderAccent) -> some View {
        modifier(MtgCardFrame(borderColor: borderColor))
    }

    /// Apply a subtle card glow for depth
    func mtgCardGlow(color: Color = .mtgGold, radius: CGFloat = 8, opacity: Double = 0.15) -> some View {
        modifier(MtgCardGlow(color: color, radius: radius, opacity: opacity))
    }

    /// Apply gold shimmer/metallic gradient to text
    func mtgGoldShimmer() -> some View {
        modifier(MtgGoldShimmer())
    }
}

// MARK: - Reusable Styled Components

/// Ornate divider with a diamond character
struct OrnateDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.mtgDivider)
                .frame(height: 1)
            Text("\u{25C6}")
                .font(.caption2)
                .foregroundStyle(Color.mtgGold)
            Rectangle()
                .fill(Color.mtgDivider)
                .frame(height: 1)
        }
    }
}

/// Section header styled like a card type line
struct MtgSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Color.mtgGold)
            .kerning(1.5)
    }
}

/// MTG-styled text field with gold border
struct MtgTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .never

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .foregroundStyle(Color.mtgTextPrimary)
        .background(Color.mtgCardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.mtgDivider, lineWidth: 1)
        )
        .autocorrectionDisabled()
    }
}

/// Stat box styled like power/toughness with subtle color gradient
struct MtgStatBox: View {
    let value: String
    let label: String
    var color: Color = .mtgTextPrimary

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.mtgTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            ZStack {
                Color.mtgCardElevated
                LinearGradient(
                    colors: [color.opacity(0.08), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// Error message banner
struct MtgErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.mtgError)
                .font(.caption)
            Text(message)
                .foregroundStyle(Color.mtgError)
                .font(.caption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}
