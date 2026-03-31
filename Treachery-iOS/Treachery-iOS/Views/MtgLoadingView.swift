//
//  MtgLoadingView.swift
//  Treachery-iOS
//

import SwiftUI

struct MtgLoadingView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color.mtgGold)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.mtgTextSecondary)
        }
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.mtgBackground.ignoresSafeArea()
        MtgLoadingView()
    }
}
#endif
