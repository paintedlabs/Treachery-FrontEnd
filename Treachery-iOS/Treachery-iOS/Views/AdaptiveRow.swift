//
//  AdaptiveRow.swift
//  Treachery-iOS
//

import SwiftUI

/// A row with a leading part, such as a name, and a trailing part, such as a
/// value or buttons: side by side, and stacked at the accessibility text
/// sizes, where side by side would break words in the middle.
struct AdaptiveRow<Leading: View, Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                leading
                trailing
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack {
                leading
                Spacer()
                trailing
            }
        }
    }
}
