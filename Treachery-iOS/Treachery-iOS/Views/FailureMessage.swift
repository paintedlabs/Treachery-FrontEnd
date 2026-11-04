//
//  FailureMessage.swift
//  Treachery-iOS
//

import Accessibility
import SwiftUI

/// A failure said in a line of text, such as why signing in or a rename
/// didn't work: primary-colored text after a red warning icon. `mtgError`
/// text is below the 4.5:1 contrast minimum on this app's backgrounds
/// (about 3.4:1 on cards and 3.8:1 on the screen background).
struct FailureMessage: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.mtgError)
        }
        .font(.footnote)
        .foregroundStyle(Color.mtgTextPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Says `message` to VoiceOver, if there is one. VoiceOver doesn't read
    /// a failure that appears after a button was tapped, away from that
    /// button, so the screen that ran the action says it, after every
    /// attempt: a repeated failure changes nothing on screen.
    static func announce(_ message: String?) {
        guard let message else { return }
        AccessibilityNotification.Announcement(message).post()
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.mtgBackground.ignoresSafeArea()
        FailureMessage(message: UserFacingError.incorrectEmailOrPassword.message)
            .padding()
    }
}
#endif
