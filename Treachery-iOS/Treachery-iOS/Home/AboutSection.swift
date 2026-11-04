//
//  AboutSection.swift
//  Treachery-iOS
//

import SwiftUI

/// The bottom of the Profile screen: the app's version, links to support and
/// the privacy policy, credits for the card content, and the notice the
/// Wizards of the Coast Fan Content Policy requires.
struct AboutSection: View {
    /// The version and build, such as "1.2 (34)".
    let version: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MtgSectionHeader(title: "About")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)

            OrnateDivider()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .accessibilityHidden(true)

            AdaptiveRow {
                Text("Version")
                    .foregroundStyle(Color.mtgTextPrimary)
            } trailing: {
                Text(verbatim: version)
                    .foregroundStyle(Color.mtgTextSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)

            webLink("Support", to: AppInfo.supportURL)
            webLink("Privacy Policy", to: AppInfo.privacyPolicyURL)

            VStack(alignment: .leading, spacing: 4) {
                Text("Credits")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.mtgTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Identity cards and the Treachery format by MTGTreachery.net.")
                Text("Plane card images from Scryfall.")
            }
            .font(.subheadline)
            .foregroundStyle(Color.mtgTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Text(verbatim: AppInfo.fanContentNotice)
                .font(.footnote)
                .foregroundStyle(Color.mtgTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mtgCardFrame()
    }

    /// A row that opens a page of the Treachery website in the browser.
    private func webLink(_ title: LocalizedStringKey, to url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Text(title)
                    .foregroundStyle(Color.mtgGold)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(Color.mtgTextSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityHint("Opens in your browser.")
    }
}

#if DEBUG
#Preview {
    ScrollView {
        AboutSection(version: "1.0 (42)")
            .padding()
    }
    .background(Color.mtgBackground)
}
#endif
