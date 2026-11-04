import Testing
import SwiftUI
@testable import Treachery_iOS

/// The colors used for caption- and body-size text, against the cards they
/// sit on. WCAG AA asks 4.5:1 for text that size. mtgSurface is the lighter
/// of the two dark backgrounds, so text that passes on it passes on
/// mtgBackground too.
@MainActor
struct TextContrastTests {

    /// WCAG relative luminance, from the linear sRGB components SwiftUI
    /// resolves a color to.
    private func luminance(of color: Color) -> Double {
        let resolved = color.resolve(in: EnvironmentValues())
        return 0.2126 * Double(resolved.linearRed)
            + 0.7152 * Double(resolved.linearGreen)
            + 0.0722 * Double(resolved.linearBlue)
    }

    private func contrast(of text: Color, on background: Color) -> Double {
        let (text, background) = (luminance(of: text), luminance(of: background))
        return (max(text, background) + 0.05) / (min(text, background) + 0.05)
    }

    @Test(arguments: Role.allCases)
    func roleLabelsAreReadable(role: Role) {
        #expect(contrast(of: role.textColor, on: .mtgSurface) >= 4.5)
    }

    @Test func errorTextIsReadable() {
        #expect(contrast(of: .mtgErrorText, on: .mtgSurface) >= 4.5)
    }
}
