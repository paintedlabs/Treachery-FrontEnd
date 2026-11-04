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
            retryProfileSetup: {},
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

    @Test func failedRenameKeepsTheOldNameAndSaysWhyInPlainWords() async {
        await viewModel.loadData(userId: "u1")
        viewModel.startEditing()
        viewModel.editedName = "New Name"
        firestore.userWriteError = NSError(
            domain: "FIRFirestoreErrorDomain",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."]
        )

        await viewModel.saveName()

        #expect(viewModel.user?.displayName == "Old Name")
        #expect(viewModel.renameState == .failed(.notPermitted))
        #expect(viewModel.renameFailureMessage == "Your new name wasn't saved. You don't have permission to do that.")
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

    @Test func nothingIsShownUntilTheFirstLoadFinishes() async {
        #expect(viewModel.profile.phase == .idle)
        #expect(viewModel.stats.phase == .idle)
        var phasesMidLoad: [LoadablePhase]?
        var hadValueMidLoad: Bool?
        firestore.whileGettingFinishedGames = { [viewModel] in
            phasesMidLoad = [viewModel.profile.phase, viewModel.stats.phase]
            hadValueMidLoad = viewModel.profile.value != nil || viewModel.stats.value != nil
        }

        await viewModel.loadData(userId: "u1")

        // The profile and its stats show together, not one beside a spinner.
        #expect(phasesMidLoad == [.loading, .loading])
        #expect(hadValueMidLoad == false)
        #expect(viewModel.profile.phase == .loaded)
        #expect(viewModel.stats.phase == .loaded)
        #expect(viewModel.user?.displayName == "Old Name")
    }

    @Test func failedLoadSaysWhyInPlainWordsThenRetryLoads() async {
        firestore.errorToThrow = NSError(
            domain: "FIRFirestoreErrorDomain",
            code: 14,
            userInfo: [NSLocalizedDescriptionKey: "Failed to get document because the client is offline."]
        )

        await viewModel.loadData(userId: "u1")

        #expect(viewModel.profile.phase == .failed)
        #expect(viewModel.profile.failure == .serverUnreachable)
        // Nothing to show, rather than an endless "Loading stats...".
        #expect(viewModel.profile.value == nil)
        #expect(viewModel.user == nil)

        firestore.errorToThrow = nil
        await viewModel.loadData(userId: "u1")

        #expect(viewModel.profile.phase == .loaded)
        #expect(viewModel.profile.failure == nil)
        #expect(viewModel.user?.displayName == "Old Name")
    }

    @Test func failedRefreshKeepsTheProfileOnScreen() async {
        await viewModel.loadData(userId: "u1")
        firestore.errorToThrow = NSError(domain: "FIRFirestoreErrorDomain", code: 4)
        var nameMidRefresh: String?
        firestore.whileGettingFinishedGames = { [viewModel] in
            nameMidRefresh = viewModel.user?.displayName
        }

        await viewModel.loadData(userId: "u1")

        #expect(nameMidRefresh == "Old Name")
        #expect(viewModel.profile.phase == .failed)
        #expect(viewModel.profile.failure == .timedOut)
        #expect(viewModel.user?.displayName == "Old Name")
        #expect(viewModel.user?.elo == 1640)
    }

    /// A profile that is missing or unreadable used to leave a spinner
    /// running for good, and Try Again only read it again. Now Try Again
    /// first sets up a profile that couldn't be at sign-in, then reads it.
    @Test func tryAgainSetsUpAMissingProfileThenLoadsIt() async {
        firestore.usersToReturn = [:]
        var setupAttempts = 0
        let viewModel = ProfileViewModel(
            session: SessionEndingSpy(),
            retryProfileSetup: { [firestore] in
                setupAttempts += 1
                // This time the setup creates the profile.
                firestore.usersToReturn["u1"] = TreacheryUser(
                    id: "u1",
                    displayName: "Player",
                    friendIds: [],
                    createdAt: Date(timeIntervalSince1970: 1_000_000)
                )
            },
            firestoreManager: firestore,
            cloudFunctions: MockCloudFunctions(),
            trackEvent: { _ in }
        )

        await viewModel.loadData(userId: "u1")

        #expect(viewModel.profile.phase == .failed)
        #expect(viewModel.profile.failure == .profileNotSetUp)
        #expect(viewModel.user == nil)
        // Showing the screen doesn't retry the setup; Try Again does.
        #expect(setupAttempts == 0)

        await viewModel.retry(userId: "u1")

        #expect(setupAttempts == 1)
        #expect(viewModel.profile.phase == .loaded)
        #expect(viewModel.profile.failure == nil)
        #expect(viewModel.user?.displayName == "Player")
    }

    /// The profile setup can finish while Profile is open, as when the name
    /// prompt over it closes. Only then does Profile read the profile again:
    /// before, it may not exist, or still have its placeholder name.
    @Test("Loads again only once the profile setup is finished", arguments: [
        (ProfileSetupState.noAccount, false),
        (ProfileSetupState.pending, false),
        (ProfileSetupState.onHold, false),
        (ProfileSetupState.needsName, false),
        (ProfileSetupState.finished, true),
    ])
    func loadsAgainOnlyOnceTheProfileSetupIsFinished(state: ProfileSetupState, loadsAgain: Bool) async {
        await viewModel.loadData(userId: "u1")
        firestore.usersToReturn["u1"]?.displayName = "New Name"

        await viewModel.profileSetupDidChange(to: state, userId: "u1")

        #expect(viewModel.user?.displayName == (loadsAgain ? "New Name" : "Old Name"))
    }

    /// Only the newest load shows what it read. Try Again's load, say, can
    /// still be on its way when the name prompt closes and Profile loads
    /// again; arriving last, it mustn't bring back the name it read.
    @Test func aLoadThatANewerOneOvertookChangesNothing() async {
        firestore.whileReturningUser = { [viewModel, firestore] in
            // While this load's answer is on its way, the name changes and a
            // newer load shows it.
            firestore.usersToReturn["u1"]?.displayName = "New Name"
            await viewModel.loadData(userId: "u1")
        }

        await viewModel.loadData(userId: "u1")

        #expect(viewModel.profile.phase == .loaded)
        #expect(viewModel.user?.displayName == "New Name")
    }

    /// Offline with the profile cached but no finished games, Firestore
    /// answers the games with nothing it can vouch for. The profile still
    /// shows, and only the stats say they need a connection: stale beats
    /// blank.
    @Test func offlineWithNoGamesCachedStillShowsTheProfile() async {
        firestore.finishedGamesError = FirestoreReadError.nothingCachedOffline

        await viewModel.loadData(userId: "u1")

        #expect(viewModel.profile.phase == .loaded)
        #expect(viewModel.user?.displayName == "Old Name")
        #expect(viewModel.user?.elo == 1640)
        #expect(viewModel.stats.phase == .failed)
        #expect(viewModel.stats.value == nil)
        #expect(viewModel.statsFailureMessage == "Stats need a connection. Try again when you're back online.")
    }

    @Test func failedStatsRefreshKeepsTheLastStats() async {
        firestore.finishedGamesToReturn = [game("won", winningTeam: "leader")]
        firestore.playersByGameToReturn = ["won": [seat(role: .leader)]]
        await viewModel.loadData(userId: "u1")
        firestore.finishedGamesError = NSError(domain: "FIRFirestoreErrorDomain", code: 4)

        await viewModel.loadData(userId: "u1")

        #expect(viewModel.profile.phase == .loaded)
        #expect(viewModel.stats.failure == .timedOut)
        #expect(viewModel.stats.value?.wins == 1)
        #expect(viewModel.statsFailureMessage == "Your stats didn't load. The server took too long to respond. Try again.")

        firestore.finishedGamesError = nil
        await viewModel.loadData(userId: "u1")

        #expect(viewModel.stats.phase == .loaded)
        #expect(viewModel.statsFailureMessage == nil)
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

        let stats = try #require(viewModel.stats.value)
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

        let stats = try #require(viewModel.stats.value)
        #expect(stats.totalGames == 2)
        #expect(stats.wins == 1)
        #expect(stats.losses == 0)
        #expect(stats.unknownResults == 1)
        // A game whose players didn't load doesn't fail the stats or the profile.
        #expect(viewModel.stats.failure == nil)
        #expect(viewModel.profile.failure == nil)
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
