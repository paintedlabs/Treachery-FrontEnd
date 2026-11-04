import Testing
import SwiftUI
@testable import Treachery_iOS

/// The colors used for caption- and body-size text, against what they sit
/// on. WCAG AA asks 4.5:1 for text that size. mtgSurface is the lighter of
/// the two dark backgrounds, so text that passes on it passes on
/// mtgBackground too. Error text also sits on the board, which the signed-in
/// player's color tints, and on the spectator bar's red wash over that.
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

    /// `top` at `opacity` over `bottom`, mixed as the screen mixes them: in
    /// sRGB's encoded values, not in linear light.
    private func composite(_ top: Color, opacity: Double, over bottom: Color) -> Color {
        let environment = EnvironmentValues()
        let (top, bottom) = (top.resolve(in: environment), bottom.resolve(in: environment))
        func mix(_ top: Float, _ bottom: Float) -> Float {
            Float(opacity) * top + Float(1 - opacity) * bottom
        }
        return Color(Color.Resolved(
            red: mix(top.red, bottom.red), green: mix(top.green, bottom.green), blue: mix(top.blue, bottom.blue)
        ))
    }

    /// The board under `playerColorName`, as GameBoardView draws it.
    private func board(tintedBy playerColorName: String) throws -> Color {
        let playerColor = try #require(PlayerColors.palette.first { $0.name == playerColorName })
        return composite(playerColor.color, opacity: GameBoardView.playerTintOpacity, over: .mtgBackground)
    }

    @Test(arguments: Role.allCases)
    func roleLabelsAreReadable(role: Role) {
        #expect(contrast(of: role.textColor, on: .mtgSurface) >= 4.5)
    }

    @Test func errorTextIsReadable() {
        #expect(contrast(of: .mtgErrorText, on: .mtgSurface) >= 4.5)
    }

    /// The error banners in the pinned controls.
    @Test(arguments: PlayerColors.palette.map(\.name))
    func errorTextIsReadableOnTheBoard(tintedBy playerColorName: String) throws {
        #expect(contrast(of: .mtgErrorText, on: try board(tintedBy: playerColorName)) >= 4.5)
    }

    /// "You've Been Eliminated" and Leave Game.
    @Test(arguments: PlayerColors.palette.map(\.name))
    func errorTextIsReadableOnTheSpectatorBar(overBoardTintedBy playerColorName: String) throws {
        let bar = composite(.mtgError, opacity: SpectatorBar.washOpacity, over: try board(tintedBy: playerColorName))
        #expect(contrast(of: .mtgErrorText, on: bar) >= 4.5)
    }
}
