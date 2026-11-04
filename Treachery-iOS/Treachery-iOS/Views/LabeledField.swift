//
//  LabeledField.swift
//  Treachery-iOS
//

import SwiftUI

/// A text field whose name can be read at every text size: inside the field
/// as its placeholder at the standard sizes, and above the field at the
/// accessibility sizes, where it can wrap. There a one-line placeholder such
/// as "Confirm Password" no longer fits a small phone's field and is cut off.
struct LabeledField<Field: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let name: LocalizedStringKey
    private let field: (Text) -> Field

    /// - Parameters:
    ///   - name: The field's name. The field gives VoiceOver the same name.
    ///   - field: Builds the field around the placeholder it's given: the
    ///     name, or nothing while the name is above the field.
    init(_ name: LocalizedStringKey, @ViewBuilder field: @escaping (_ placeholder: Text) -> Field) {
        self.name = name
        self.field = field
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if dynamicTypeSize.isAccessibilitySize {
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(Color.mtgTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    // The field says its own name to VoiceOver.
                    .accessibilityHidden(true)
            }
            field(dynamicTypeSize.isAccessibilitySize ? Text(verbatim: "") : Text(name))
        }
    }
}
