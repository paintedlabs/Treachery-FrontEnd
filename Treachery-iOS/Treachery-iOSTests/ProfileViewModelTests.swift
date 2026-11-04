import Testing
import Foundation
@testable import Treachery_iOS

@MainActor
@Suite("Profile rename and stats")
struct ProfileViewModelTests {

    private let firestore = MockFirestoreManager()
    private let viewModel: ProfileViewModel

    init() {
        firestore.usersToReturn["u1"] = TreacheryUser(
            id: "u1",
            displayName: "Old Name",
            friendIds: ["f1"],
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            elo: 1640
        )
        viewModel = ProfileViewModel(
            session: SessionEndingSpy(),
            firestoreManager: firestore,
            cloudFunctions: MockCloudFunctions(),
            trackEvent: { _ in }
        )
    }

    // MARK: - Rename

    @Test func renameWritesOnlyTheDisplayName() async throws {
        await viewModel.loadData(userId: "u1")
        viewModel.startEditing()
        viewModel.editedName = "  New Name  "

        await viewModel.saveName()

        let call = try #require(firestore.updateDisplayNameCalls.first)
        #expect(firestore.updateDisplayNameCalls.count == 1)
        #expect(call.name == "New Name")
        #expect(call.userId == "u1")
        // No other profile write: elo, friends and created_at are never sent back.
        #expect(firestore.userWriteCount == 1)
        #expect(viewModel.user?.displayName == "New Name")
        #expect(viewModel.user?.elo == 1640)
        #expect(viewModel.renameState == .idle)
        #expect(!viewModel.isEditingName)
        #expect(viewModel.renameFailureMessage == nil)
    }

    @Test func nameFieldStaysOpenWhileTheRenameSaves() async {
        await viewModel.loadData(userId: "u1")
        viewModel.startEditing()
        viewModel.editedName = "New Name"
        var stateMidSave: RenameState?
        var isEditingMidSave: Bool?
        firestore.whileUpdatingDisplayName = { [viewModel] in
            stateMidSave = viewModel.renameState
            isEditingMidSave = viewModel.isEditingName
            // Edit is ignored, and a second Save sends nothing.
            viewModel.startEditing()
            await viewModel.saveName()
        }

        await viewModel.saveName()

        #expect(stateMidSave == .saving)
        #expect(isEditingMidSave == true)
        #expect(firestore.updateDisplayNameCalls.count == 1)
        #expect(viewModel.renameState == .idle)
    }

    @Test func failedRenameKeepsTheOldNameAndSaysSo() async {
        await viewModel.loadData(userId: "u1")
        viewModel.startEditing()
        viewModel.editedName = "New Name"
        firestore.userWriteError = NSError(domain: "FIRFirestoreErrorDomain", code: 7)

        await viewModel.saveName()

        #expect(viewModel.user?.displayName == "Old Name")
        #expect(viewModel.renameState == .failed(message: ProfileViewModel.ProfileMessage.renameFailed))
        #expect(viewModel.renameFailureMessage == ProfileViewModel.ProfileMessage.renameFailed)
        #expect(!viewModel.isEditingName)
        #expect(!viewModel.isSavingName)
    }

    @Test func editingAgainClearsTheRenameFailure() async {
        await viewModel.loadData(userId: "u1")
        viewModel.startEditing()
        viewModel.editedName = "New Name"
        firestore.userWriteError = NSError(domain: "FIRFirestoreErrorDomain", code: 7)
        await viewModel.saveName()

        viewModel.startEditing()

        #expect(viewModel.renameState == .editing)
        #expect(viewModel.renameFailureMessage == nil)
        #expect(viewModel.editedName == "Old Name")
    }

    @Test func blankNameIsNotSaved() async {
        await viewModel.loadData(userId: "u1")
        viewModel.startEditing()
        viewModel.editedName = "   "

        await viewModel.saveName()

        #expect(firestore.userWriteCount == 0)
        #expect(viewModel.renameState == .editing)
    }

    @Test func saveWithoutEditingSendsNothing() async {
        await viewModel.loadData(userId: "u1")
        viewModel.editedName = "New Name"

        await viewModel.saveName()

        #expect(firestore.userWriteCount == 0)
        #expect(viewModel.renameState == .idle)
    }

    // MARK: - Loading

    @Test func failedLoadShowsPlainText() async {
        firestore.errorToThrow = NSError(
            domain: "FIRFirestoreErrorDomain",
            code: 14,
            userInfo: [NSLocalizedDescriptionKey: "Failed to get document because the client is offline."]
        )

        await viewModel.loadData(userId: "u1")

        #expect(viewModel.errorMessage == ProfileViewModel.ProfileMessage.loadFailed)
    }

    @Test func statsCountOnlyDecidedGamesInTheWinRate() async throws {
        firestore.finishedGamesToReturn = [
            game("won", winningTeam: "leader"),
            game("lost", winningTeam: "traitor"),
            game("life-tracker-1", mode: .none),
            game("life-tracker-2", mode: .none),
        ]
        firestore.playersByGameToReturn = [
            "won": [seat(role: .leader)],
            "lost": [seat(role: .assassin)],
            "life-tracker-1": [seat(role: nil)],
            "life-tracker-2": [seat(role: nil)],
        ]

        await viewModel.loadData(userId: "u1")

        let stats = try #require(viewModel.gameStats)
        #expect(stats.totalGames == 4)
        #expect(stats.wins == 1)
        #expect(stats.losses == 1)
        #expect(stats.unknownResults == 0)
        #expect(stats.winRateText == "50%")
    }

    @Test func gamesWhosePlayersFailToLoadAreReportedAsUnknown() async throws {
        firestore.finishedGamesToReturn = [
            game("won", winningTeam: "leader"),
            game("players-failed", winningTeam: "leader"),
        ]
        firestore.playersByGameToReturn = ["won": [seat(role: .leader)]]
        firestore.playersErrorsByGame = ["players-failed": NSError(domain: "FIRFirestoreErrorDomain", code: 14)]

        await viewModel.loadData(userId: "u1")

        let stats = try #require(viewModel.gameStats)
        #expect(stats.totalGames == 2)
        #expect(stats.wins == 1)
        #expect(stats.losses == 0)
        #expect(stats.unknownResults == 1)
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - Fixtures

    private func game(_ id: String, mode: GameMode = .treachery, winningTeam: String? = nil) -> Game {
        Game(
            id: id,
            code: "ABCD",
            hostId: "host",
            state: .finished,
            gameMode: mode,
            maxPlayers: 8,
            startingLife: 40,
            winningTeam: winningTeam,
            playerIds: ["u1", "u2"],
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    private func seat(role: Role?) -> Player {
        Player(
            id: "seat-u1",
            orderId: 0,
            userId: "u1",
            displayName: "Old Name",
            role: role,
            identityCardId: nil,
            lifeTotal: 40,
            isEliminated: false,
            isUnveiled: false,
            joinedAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }
}
