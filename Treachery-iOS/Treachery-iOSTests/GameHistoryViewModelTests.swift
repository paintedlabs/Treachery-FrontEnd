import Testing
import Foundation
@testable import Treachery_iOS

@MainActor
@Suite("Game history")
struct GameHistoryViewModelTests {

    private let firestore = MockFirestoreManager()
    private let viewModel: GameHistoryViewModel

    init() {
        viewModel = GameHistoryViewModel(firestoreManager: firestore)
    }

    @Test func nothingIsShownUntilTheFirstLoadFinishes() async {
        #expect(viewModel.history == .idle)
        var stateMidLoad: Loadable<GameHistory, UserFacingError>?
        firestore.whileGettingFinishedGames = { [viewModel] in
            stateMidLoad = viewModel.history
        }

        await viewModel.loadHistory(userId: "u1")

        #expect(stateMidLoad == .loading(previous: nil))
        #expect(viewModel.history == .loaded(GameHistory(games: [], playersByGame: [:])))
    }

    @Test func loadShowsGamesWithTheirPlayers() async {
        firestore.finishedGamesToReturn = [game("g1"), game("g2")]
        firestore.playersByGameToReturn = ["g1": [seat("g1")], "g2": [seat("g2")]]

        await viewModel.loadHistory(userId: "u1")

        #expect(viewModel.history == .loaded(GameHistory(
            games: [game("g1"), game("g2")],
            playersByGame: ["g1": [seat("g1")], "g2": [seat("g2")]]
        )))
    }

    @Test func gameWhosePlayersFailToLoadIsShownWithoutThem() async {
        firestore.finishedGamesToReturn = [game("g1"), game("g2")]
        firestore.playersByGameToReturn = ["g1": [seat("g1")]]
        firestore.playersErrorsByGame = ["g2": NSError(domain: "FIRFirestoreErrorDomain", code: 14)]

        await viewModel.loadHistory(userId: "u1")

        #expect(viewModel.history == .loaded(GameHistory(
            games: [game("g1"), game("g2")],
            playersByGame: ["g1": [seat("g1")]]
        )))
    }

    /// "No games yet" used to show beside the error that explained it.
    @Test func failedLoadSaysWhyThenRetryLoads() async {
        firestore.finishedGamesError = NSError(
            domain: "FIRFirestoreErrorDomain",
            code: 14,
            userInfo: [NSLocalizedDescriptionKey: "Failed to get documents because the client is offline."]
        )

        await viewModel.loadHistory(userId: "u1")

        #expect(viewModel.history == .failed(.serverUnreachable, previous: nil))

        firestore.finishedGamesError = nil
        firestore.finishedGamesToReturn = [game("g1")]
        await viewModel.loadHistory(userId: "u1")

        #expect(viewModel.history == .loaded(GameHistory(games: [game("g1")], playersByGame: ["g1": []])))
    }

    @Test func failedRefreshKeepsTheGamesOnScreen() async {
        firestore.finishedGamesToReturn = [game("g1")]
        firestore.playersByGameToReturn = ["g1": [seat("g1")]]
        await viewModel.loadHistory(userId: "u1")
        let shown = GameHistory(games: [game("g1")], playersByGame: ["g1": [seat("g1")]])
        firestore.finishedGamesError = NSError(domain: "FIRFirestoreErrorDomain", code: 4)
        var stateMidRefresh: Loadable<GameHistory, UserFacingError>?
        firestore.whileGettingFinishedGames = { [viewModel] in
            stateMidRefresh = viewModel.history
        }

        await viewModel.loadHistory(userId: "u1")

        #expect(stateMidRefresh == .loading(previous: shown))
        #expect(viewModel.history == .failed(.timedOut, previous: shown))
    }

    // MARK: - Fixtures

    private func game(_ id: String) -> Game {
        Game(
            id: id,
            code: "ABCD",
            hostId: "host",
            state: .finished,
            gameMode: .treachery,
            maxPlayers: 8,
            startingLife: 40,
            winningTeam: "leader",
            playerIds: ["u1", "u2"],
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    private func seat(_ gameId: String) -> Player {
        Player(
            id: "seat-\(gameId)",
            orderId: 0,
            userId: "u1",
            displayName: "Ada",
            role: .leader,
            identityCardId: nil,
            lifeTotal: 40,
            isEliminated: false,
            isUnveiled: false,
            joinedAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }
}
