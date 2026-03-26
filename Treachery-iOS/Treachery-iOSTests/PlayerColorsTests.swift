import Testing
@testable import Treachery_iOS

struct PlayerColorsTests {

    @Test func paletteHas10Colors() {
        #expect(PlayerColors.palette.count == 10)
    }

    @Test func allColorsHaveNames() {
        for color in PlayerColors.palette {
            #expect(!color.name.isEmpty)
        }
    }

    @Test func allColorsHaveHexValues() {
        for color in PlayerColors.palette {
            #expect(!color.hex.isEmpty)
            #expect(color.hex.count == 6 || color.hex.count == 7) // With or without #
        }
    }

    @Test func allColorsHaveUniqueHex() {
        let hexes = PlayerColors.palette.map(\.hex)
        #expect(Set(hexes).count == hexes.count)
    }

    @Test func allColorsHaveUniqueNames() {
        let names = PlayerColors.palette.map(\.name)
        #expect(Set(names).count == names.count)
    }
}
