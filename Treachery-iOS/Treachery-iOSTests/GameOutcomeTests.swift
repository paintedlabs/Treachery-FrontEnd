import Testing
import Foundation
@testable import Treachery_iOS

/// Fixtures shared by the win-rule and stats suites.
private enum Fixture {
    static func game(
        _ id: String = "g1",
        mode: GameMode = .treachery,
        winningTeam: String? = nil,
        winners: [String] = []
    ) -> Game {
        Game(
            id: id,
            code: "ABCD",
            hostId: "host",
            state: .finished,
            gameMode: mode,
            maxPlayers: 8,
            startingLife: 40,
            winningTeam: winningTeam,
            playerIds: ["u1", "u2", "u3", "u4"],
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            winnerUserIds: winners
        )
    }

    static func seat(_ userId: String, role: Role?) -> Player {
        Player(
            id: "seat-\(userId)",
            orderId: 0,
            userId: userId,
            displayName: userId,
            role: role,
            identityCardId: nil,
            lifeTotal: 40,
            isEliminated: false,
            isUnveiled: false,
            joinedAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }
}

/// Every winning team against every role it can be scored for.
private let treacheryTeamCases: [(winningTeam: Role, role: Role, expected: GameOutcome)] = [
    (.leader, .leader, .won),
    (.leader, .guardian, .won),
    (.leader, .assassin, .lost),
    (.leader, .traitor, .lost),
    (.assassin, .assassin, .won),
    (.assassin, .leader, .lost),
    (.assassin, .guardian, .lost),
    (.assassin, .traitor, .lost),
    (.traitor, .traitor, .won),
    (.traitor, .leader, .lost),
    (.traitor, .guardian, .lost),
    (.traitor, .assassin, .lost),
]

@Suite("Game outcome (the shared win rule)")
struct GameOutcomeTests {

    @Test("Treachery scores by team; Guardians share the Leader's win", arguments: treacheryTeamCases)
    func treacheryTeams(winningTeam: Role, role: Role, expected: GameOutcome) {
        let game = Fixture.game(winningTeam: winningTeam.rawValue)
        #expect(game.outcome(forUserId: "u1", role: role) == expected)
    }

    @Test func treacheryPlanechaseScoresByTeamToo() {
        let game = Fixture.game(mode: .treacheryPlanechase, winningTeam: "assassin")
        #expect(game.outcome(forUserId: "u1", role: .assassin) == .won)
        #expect(game.outcome(forUserId: "u2", role: .leader) == .lost)
    }

    @Test func treacheryGameWithoutAWinnerHasNoWinner() {
        // The host ended it early.
        let game = Fixture.game(winningTeam: nil)
        #expect(game.outcome(forUserId: "u1", role: .leader) == .noWinner)
        #expect(game.outcome(forUserId: "u1", role: nil) == .noWinner)
    }

    @Test func treacheryGameWithUnknownSeatHasAnUnknownResult() {
        // The user's seat didn't load, so their team is unknown: neither a
        // win nor a loss, and not a game without a winner either.
        let game = Fixture.game(winningTeam: "leader")
        #expect(game.outcome(forUserId: "u1", role: nil) == .unknown)
    }

    @Test func unrecognizedWinningTeamHasAnUnknownResult() {
        let game = Fixture.game(winningTeam: "pirates")
        #expect(game.outcome(forUserId: "u1", role: .leader) == .unknown)
    }

    @Test func treacheryIgnoresWinnerUserIds() {
        // onGameFinished scores Treachery modes by team only.
        let game = Fixture.game(winningTeam: nil, winners: ["u1"])
        #expect(game.outcome(forUserId: "u1", role: .leader) == .noWinner)
    }

    @Test(arguments: [GameMode.planechase, .none])
    func otherModesUseTheHostsPickOfWinners(mode: GameMode) {
        let game = Fixture.game(mode: mode, winners: ["u1", "u3"])
        #expect(game.outcome(forUserId: "u1", role: nil) == .won)
        #expect(game.outcome(forUserId: "u3", role: nil) == .won)
        #expect(game.outcome(forUserId: "u2", role: nil) == .lost)
    }

    @Test(arguments: [GameMode.planechase, .none])
    func otherModesWithoutWinnersHaveNoWinner(mode: GameMode) {
        let game = Fixture.game(mode: mode, winningTeam: nil, winners: [])
        #expect(game.outcome(forUserId: "u1", role: nil) == .noWinner)
    }
}

@Suite("Profile game stats")
struct GameStatsTests {

    @Test func winRateCountsOnlyGamesWithAWinner() {
        // 2 wins, 2 losses, and 4 Life Tracker games nobody won.
        let stats = GameStats(totalGames: 8, wins: 2, losses: 2, unknownResults: 0, roleBreakdown: [:])
        #expect(stats.winRate == 0.5)
        #expect(stats.winRateText == "50%")
    }

    @Test func winRateIsBlankWithoutDecidedGames() {
        let stats = GameStats(totalGames: 3, wins: 0, losses: 0, unknownResults: 0, roleBreakdown: [:])
        #expect(stats.winRate == nil)
        #expect(stats.winRateText == "--")
    }

    @Test(arguments: [
        (wins: 2, losses: 1, expected: "67%"),
        (wins: 1, losses: 7, expected: "13%"),
        (wins: 1, losses: 2, expected: "33%"),
        (wins: 3, losses: 0, expected: "100%"),
        (wins: 0, losses: 4, expected: "0%"),
    ])
    func winRateRoundsLikeWeb(wins: Int, losses: Int, expected: String) {
        let stats = GameStats(totalGames: wins + losses, wins: wins, losses: losses, unknownResults: 0, roleBreakdown: [:])
        #expect(stats.winRateText == expected)
    }

    @Test func statsFromGamesUseTheSharedRule() {
        let games = [
            Fixture.game("won-as-guardian", winningTeam: "leader"),
            Fixture.game("lost-as-guardian", winningTeam: "assassin"),
            Fixture.game("ended-early", winningTeam: nil),
            Fixture.game("seat-missing", winningTeam: "leader"),
            Fixture.game("planechase-win", mode: .planechase, winners: ["u1"]),
            Fixture.game("life-tracker-undecided", mode: .none),
        ]
        let playersByGame = [
            "won-as-guardian": [Fixture.seat("u1", role: .guardian), Fixture.seat("u2", role: .assassin)],
            "lost-as-guardian": [Fixture.seat("u1", role: .guardian), Fixture.seat("u2", role: .assassin)],
            "ended-early": [Fixture.seat("u1", role: .traitor)],
            "planechase-win": [Fixture.seat("u1", role: nil), Fixture.seat("u2", role: nil)],
            "life-tracker-undecided": [Fixture.seat("u1", role: nil)],
        ]

        let stats = GameStats(games: games, playersByGame: playersByGame, userId: "u1")

        #expect(stats.totalGames == 6)
        #expect(stats.wins == 2)
        #expect(stats.losses == 1)
        // The game whose seat didn't load is neither a win nor a loss, and
        // is reported as unknown so the stats can say they are partial.
        #expect(stats.unknownResults == 1)
        #expect(stats.winRateText == "67%")
        #expect(stats.roleBreakdown == [.guardian: 2, .traitor: 1])
    }
}
