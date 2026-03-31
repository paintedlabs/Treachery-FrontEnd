//
//  MtgBadge.swift
//  Treachery-iOS
//

import SwiftUI

struct MtgBadge: View {
    let text: String
    var foregroundColor: Color = .mtgBackground
    var backgroundColor: Color = .mtgGold
    var font: Font = .caption2
    var fontWeight: Font.Weight = .bold

    var body: some View {
        Text(text)
            .font(font)
            .fontWeight(fontWeight)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .clipShape(Capsule())
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.mtgBackground.ignoresSafeArea()
        VStack(spacing: 12) {
            MtgBadge(text: "Host", foregroundColor: .mtgGold, backgroundColor: Color.mtgGold.opacity(0.15), font: .caption)
            MtgBadge(text: "UNVEILED", foregroundColor: .mtgBackground, backgroundColor: .mtgAssassin)
            MtgBadge(text: "LEADER — ALWAYS VISIBLE", foregroundColor: .mtgGold, backgroundColor: Color.mtgGold.opacity(0.15))
            MtgBadge(text: "You", foregroundColor: .mtgGold, backgroundColor: Color.mtgGold.opacity(0.15), fontWeight: .regular)
        }
    }
}
#endif
