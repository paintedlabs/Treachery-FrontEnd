//
//  LoadFailureCard.swift
//  Treachery-iOS
//

import Accessibility
import SwiftUI

/// Says that a screen's content didn't load, why, and offers to try again.
/// Shown in place of content that never loaded, or above content kept from
/// an earlier load.
///
/// Primary-colored text with a red icon and border: `mtgError` text on
/// `mtgSurface` is below the 4.5:1 contrast minimum.
struct LoadFailureCard: View {
    /// What didn't load, such as "Couldn't Load Game History". A resource,
    /// not a `String`, so the callers' literals are extracted and localized.
    let title: LocalizedStringResource
    let failure: UserFacingError
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(title)
                        .font(.headline)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.mtgError)
                }
                .foregroundStyle(Color.mtgTextPrimary)
                .accessibilityAddTraits(.isHeader)

                Text(failure.message)
                    .font(.subheadline)
                    .foregroundStyle(Color.mtgTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Button("Try Again", action: retry)
                .buttonStyle(MtgSecondaryButtonStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mtgCardFrame(borderColor: Color.mtgError.opacity(0.6))
        // The card replaces content after a load, away from wherever
        // VoiceOver focus is, so say what happened.
        .onAppear {
            let announcement = String(
                localized: "\(String(localized: title)). \(failure.message)",
                comment: "VoiceOver announcement when a screen's content didn't load: the failure's title, then why."
            )
            AccessibilityNotification.Announcement(announcement).post()
        }
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.mtgBackground.ignoresSafeArea()
        LoadFailureCard(title: "Couldn't Load Game History", failure: .offline) {}
            .padding()
    }
}
#endif
