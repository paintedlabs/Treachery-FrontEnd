import Testing
import Foundation
@testable import Treachery_iOS

struct GameModeTests {

    @Test func allCases() {
        #expect(GameMode.allCases.count == 4)
    }

    @Test func rawValues() {
        #expect(GameMode.treachery.rawValue == "treachery")
        #expect(GameMode.planechase.rawValue == "planechase")
        #expect(GameMode.treacheryPlanechase.rawValue == "treachery_planechase")
        #expect(GameMode.none.rawValue == "none")
    }

    @Test func displayNames() {
        #expect(GameMode.treachery.displayName == "Treachery")
        #expect(GameMode.planechase.displayName == "Planechase")
        #expect(GameMode.treacheryPlanechase.displayName == "Both")
        #expect(GameMode.none.displayName == "Life Tracker")
    }

    @Test func includesTreachery() {
        #expect(GameMode.treachery.includesTreachery == true)
        #expect(GameMode.treacheryPlanechase.includesTreachery == true)
        #expect(GameMode.planechase.includesTreachery == false)
        #expect(GameMode.none.includesTreachery == false)
    }

    @Test func includesPlanechase() {
        #expect(GameMode.planechase.includesPlanechase == true)
        #expect(GameMode.treacheryPlanechase.includesPlanechase == true)
        #expect(GameMode.treachery.includesPlanechase == false)
        #expect(GameMode.none.includesPlanechase == false)
    }

    @Test func decodesFromJSON() throws {
        let json = Data(#""treachery_planechase""#.utf8)
        let mode = try JSONDecoder().decode(GameMode.self, from: json)
        #expect(mode == .treacheryPlanechase)
    }

    // MARK: - Unknown modes

    @Test func allCasesListsOnlyKnownModes() {
        #expect(!GameMode.allCases.contains { $0.isUnknown })
    }

    @Test func knownRawValuesRoundTrip() {
        for mode in GameMode.allCases {
            #expect(GameMode(rawValue: mode.rawValue) == mode)
        }
    }

    @Test func unrecognisedRawValueBecomesUnknown() {
        let mode = GameMode(rawValue: "archenemy")
        #expect(mode == .unknown("archenemy"))
        #expect(mode.rawValue == "archenemy")
        #expect(mode.isUnknown)
    }

    @Test func unknownModeIncludesNeitherRuleSet() {
        let mode = GameMode.unknown("archenemy")
        #expect(!mode.includesTreachery)
        #expect(!mode.includesPlanechase)
        #expect(mode.displayName == "Unsupported Mode")
    }

    @Test func decodesUnknownModeFromJSON() throws {
        let json = Data(#""archenemy""#.utf8)
        let mode = try JSONDecoder().decode(GameMode.self, from: json)
        #expect(mode == .unknown("archenemy"))
    }
}
