//
//  WelcomeView.swift
//  Treachery-iOS
//

import SwiftUI

struct WelcomeView: View {
    let onComplete: () -> Void

    private let roles: [(name: String, color: Color, description: String)] = [
        ("Leader", .roleLeader, "Eliminate all Assassins and Traitors to win."),
        ("Guardian", .roleGuardian, "Keep the Leader alive. Eliminate all Assassins and Traitors."),
        ("Assassin", .roleAssassin, "Eliminate the Leader while at least one Assassin survives."),
        ("Traitor", .roleTraitor, "Be the last player standing."),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 32)

                Text("Welcome to Treachery")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundColor(.mtgGoldBright)
                    .multilineTextAlignment(.center)

                Text("A Game of Hidden Allegiance")
                    .font(.system(.subheadline, design: .serif))
                    .italic()
                    .foregroundColor(.mtgTextSecondary)

                OrnateDivider()
                    .padding(.vertical, 8)

                Text("Each player is secretly assigned a role. Use deception and strategy to achieve your team's goal.")
                    .font(.system(.body, design: .serif))
                    .foregroundColor(.mtgTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Role cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(roles, id: \.name) { role in
                        roleCard(name: role.name, color: role.color, description: role.description)
                    }
                }
                .padding(.horizontal, 4)

                OrnateDivider()
                    .padding(.vertical, 8)

                Link(destination: URL(string: "https://mtgtreachery.net")!) {
                    Text("Read the full rules at mtgtreachery.net")
                        .font(.system(.footnote, design: .serif))
                        .italic()
                        .foregroundColor(.mtgGold)
                }

                Button {
                    onComplete()
                } label: {
                    Text("Let's Play")
                }
                .buttonStyle(MtgPrimaryButtonStyle())
                .padding(.top, 8)

                Spacer(minLength: 32)
            }
            .padding(.horizontal)
        }
        .mtgRadialBackground()
    }

    private func roleCard(name: String, color: Color, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.system(.headline, design: .serif))
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(description)
                .font(.system(.caption, design: .serif))
                .foregroundColor(.mtgTextSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.mtgSurface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(color)
                .frame(width: 3)
        }
    }
}

// Role color convenience
private extension Color {
    static let roleLeader = Color(red: 0.894, green: 0.788, blue: 0.416)   // #E4C96A
    static let roleGuardian = Color(red: 0.298, green: 0.549, blue: 0.788) // #4C8CC9
    static let roleAssassin = Color(red: 0.788, green: 0.298, blue: 0.298) // #C94C4C
    static let roleTraitor = Color(red: 0.612, green: 0.298, blue: 0.788)  // #9C4CC9
}
