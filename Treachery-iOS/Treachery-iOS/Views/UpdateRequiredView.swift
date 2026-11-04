//
//  UpdateRequiredView.swift
//  Treachery-iOS
//

import Accessibility
import SwiftUI

/// The blocking screen for a build below `min_build` in `config/ios`. The only
/// way past it is to update, so it holds just the reason and the way to the
/// App Store.
struct UpdateRequiredView: View {
    /// Text from `config/ios`. Nil shows the default text.
    let message: String?
    /// The App Store page. Nil hides the Update button.
    let storeURL: URL?

    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 56

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: iconSize))
                        .foregroundStyle(Color.mtgGold)
                        .accessibilityHidden(true)

                    Text("Update Required")
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
                        .foregroundStyle(Color.mtgGoldBright)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    messageText
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(Color.mtgTextPrimary)
                        .multilineTextAlignment(.center)

                    if let storeURL {
                        Button {
                            openURL(storeURL)
                        } label: {
                            Text("Update")
                        }
                        .buttonStyle(MtgPrimaryButtonStyle())
                        .accessibilityHint("Opens Treachery in the App Store")
                        .padding(.top, 8)
                    } else {
                        Text("Update Treachery from the App Store.")
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(Color.mtgTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                // Centered when it fits; scrolls at large Dynamic Type sizes.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .mtgRadialBackground()
        .onAppear {
            // This screen replaces the whole app, often while VoiceOver is on
            // the splash's spinner. Announce the change so focus moves to the
            // title, the first element here.
            AccessibilityNotification.ScreenChanged().post()
        }
    }

    private var messageText: Text {
        if let message {
            // The operator's words, shown as written.
            return Text(message)
        }
        return Text("This version of Treachery is out of date. Update to the latest version to keep playing.")
    }
}

#if DEBUG
#Preview("Message and link") {
    UpdateRequiredView(
        message: "This version can't join games any more. Update to keep playing.",
        storeURL: URL(string: "https://apps.apple.com/app/id0000000000")
    )
    .preferredColorScheme(.dark)
}

#Preview("Defaults, no link") {
    UpdateRequiredView(message: nil, storeURL: nil)
        .preferredColorScheme(.dark)
}
#endif
