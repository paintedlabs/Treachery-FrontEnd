//
//  FullHeightScrollView.swift
//  Treachery-iOS
//

import SwiftUI

/// A scroll view whose content is at least as tall as the space it's given.
/// A screen laid out with `Spacer`s keeps its shape when it fits, and
/// scrolls instead of pushing its buttons off screen when it doesn't: at the
/// largest text sizes, on a small phone, or with the keyboard up. When the
/// content fits it doesn't scroll or bounce at all.
struct FullHeightScrollView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
