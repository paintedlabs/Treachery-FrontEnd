//
//  WelcomeView.swift
//  Treachery-iOS
//

import SwiftUI

private struct RoleInfo: Identifiable {
    let id: String
    let name: String
    let color: Color
    let description: String
}

private let allRoles = [
    RoleInfo(id: "leader", name: "Leader", color: .roleLeader,
             description: "Eliminate all Assassins and Traitors to win."),
    RoleInfo(id: "guardian", name: "Guardian", color: .roleGuardian,
             description: "Keep the Leader alive. Eliminate all Assassins and Traitors."),
    RoleInfo(id: "assassin", name: "Assassin", color: .roleAssassin,
             description: "Eliminate the Leader while at least one Assassin survives."),
    RoleInfo(id: "traitor", name: "Traitor", color: .roleTraitor,
             description: "Be the last player standing."),
]

struct WelcomeView: View {
    let onComplete: () -> Void

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
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(allRoles) { role in
                        roleCard(role)
                    }
                }
                .padding(.horizontal, 4)

                OrnateDivider()
                    .padding(.vertical, 8)

                Button {
                    if let url = URL(string: "https://mtgtreachery.net") {
                        UIApplication.shared.open(url)
                    }
                } label: {
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

    private func roleCard(_ role: RoleInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(role.name)
                .font(.system(.headline, design: .serif))
                .fontWeight(.bold)
                .foregroundColor(role.color)

            Text(role.description)
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
                .stroke(role.color.opacity(0.3), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(role.color)
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
