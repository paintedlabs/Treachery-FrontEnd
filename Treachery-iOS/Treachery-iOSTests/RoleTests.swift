import Testing
import Foundation
@testable import Treachery_iOS

struct RoleTests {

    // MARK: - Raw Values & CaseIterable

    @Test func allCasesExist() {
        #expect(Role.allCases.count == 4)
        #expect(Role.allCases.contains(.leader))
        #expect(Role.allCases.contains(.guardian))
        #expect(Role.allCases.contains(.assassin))
        #expect(Role.allCases.contains(.traitor))
    }

    @Test func rawValues() {
        #expect(Role.leader.rawValue == "leader")
        #expect(Role.guardian.rawValue == "guardian")
        #expect(Role.assassin.rawValue == "assassin")
        #expect(Role.traitor.rawValue == "traitor")
    }

    // MARK: - Display Names

    @Test func displayNames() {
        #expect(Role.leader.displayName == "Leader")
        #expect(Role.guardian.displayName == "Guardian")
        #expect(Role.assassin.displayName == "Assassin")
        #expect(Role.traitor.displayName == "Traitor")
    }

    // MARK: - Win Condition Text

    @Test func winConditionTextIsNonEmpty() {
        for role in Role.allCases {
            #expect(!role.winConditionText.isEmpty)
        }
    }

    // MARK: - Identifiable

    @Test func identifiableUsesRawValue() {
        for role in Role.allCases {
            #expect(role.id == role.rawValue)
        }
    }

    // MARK: - Role Distribution

    @Test func distributionForFourPlayers() {
        let dist = Role.distribution(forPlayerCount: 4)
        #expect(dist.leaders == 1)
        #expect(dist.guardians == 0)
        #expect(dist.assassins == 2)
        #expect(dist.traitors == 1)
        #expect(dist.leaders + dist.guardians + dist.assassins + dist.traitors == 4)
    }

    @Test func distributionForFivePlayers() {
        let dist = Role.distribution(forPlayerCount: 5)
        #expect(dist.leaders == 1)
        #expect(dist.guardians == 1)
        #expect(dist.assassins == 2)
        #expect(dist.traitors == 1)
        #expect(dist.leaders + dist.guardians + dist.assassins + dist.traitors == 5)
    }

    @Test func distributionForSixPlayers() {
        let dist = Role.distribution(forPlayerCount: 6)
        #expect(dist.leaders == 1)
        #expect(dist.guardians == 1)
        #expect(dist.assassins == 3)
        #expect(dist.traitors == 1)
        #expect(dist.leaders + dist.guardians + dist.assassins + dist.traitors == 6)
    }

    @Test func distributionForSevenPlayers() {
        let dist = Role.distribution(forPlayerCount: 7)
        #expect(dist.leaders == 1)
        #expect(dist.guardians == 2)
        #expect(dist.assassins == 3)
        #expect(dist.traitors == 1)
        #expect(dist.leaders + dist.guardians + dist.assassins + dist.traitors == 7)
    }

    @Test func distributionForEightPlayers() {
        let dist = Role.distribution(forPlayerCount: 8)
        #expect(dist.leaders == 1)
        #expect(dist.guardians == 2)
        #expect(dist.assassins == 3)
        #expect(dist.traitors == 2)
        #expect(dist.leaders + dist.guardians + dist.assassins + dist.traitors == 8)
    }

    @Test func distributionAlwaysHasOneLeader() {
        for count in 4...8 {
            let dist = Role.distribution(forPlayerCount: count)
            #expect(dist.leaders == 1)
        }
    }

    @Test func distributionDefaultFallback() {
        let dist = Role.distribution(forPlayerCount: 99)
        #expect(dist.leaders == 1)
        #expect(dist.guardians == 0)
        #expect(dist.assassins == 2)
        #expect(dist.traitors == 1)
    }

    // MARK: - Minimum Player Count

    @Test func minimumPlayerCountIsFour() {
        #expect(Role.minimumPlayerCount == 4)
    }

    // MARK: - Codable

    @Test func decodesFromJSON() throws {
        let json = Data(#""leader""#.utf8)
        let role = try JSONDecoder().decode(Role.self, from: json)
        #expect(role == .leader)
    }

    @Test func encodesToJSON() throws {
        let data = try JSONEncoder().encode(Role.assassin)
        let string = String(data: data, encoding: .utf8)
        #expect(string == #""assassin""#)
    }
}
