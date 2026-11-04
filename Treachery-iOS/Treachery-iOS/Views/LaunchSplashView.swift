//
//  LaunchSplashView.swift
//  Treachery-iOS
//

import SwiftUI

/// The title and spinner shown while launch work finishes: first the version
/// check, then auth. Both use this view, so moving from one to the other
/// doesn't flicker.
struct LaunchSplashView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 36

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Treachery")
                    .font(.system(size: titleSize, weight: .bold, design: .serif))
                    .foregroundStyle(Color.mtgGoldBright)
                ProgressView()
                    .tint(Color.mtgGold)
                    .accessibilityLabel("Loading")
            }
        }
    }
}
