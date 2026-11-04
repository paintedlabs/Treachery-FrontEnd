//
//  ProfileViewModel.swift
//  Treachery-iOS
//

import Foundation
import os

struct GameStats {
    let totalGames: Int
    let wins: Int
    let losses: Int
    /// Games that had a winner but whose result for this user isn't known,
    /// usually because their seat didn't load. They count toward
    /// `totalGames` but not as wins or losses, so the stats are partial.
    let unknownResults: Int
    let roleBreakdown: [Role: Int]

    /// The share of decided games won, from 0 to 1, or nil when no game had
    /// a winner. Finished games without a winner count toward `totalGames`
    /// but not here, as on web.
    var winRate: Double? {
        let decidedGames = wins + losses
        guard decidedGames > 0 else { return nil }
        return Double(wins) / Double(decidedGames)
    }

    var winRateText: String {
        guard let winRate else { return "--" }
        return "\(Int((winRate * 100).rounded()))%"
    }
}

extension GameStats {
    /// The stats for `userId` over their finished `games`, scored with the
    /// shared win rule, `Game.outcome(forUserId:role:)`.
    /// - Parameter playersByGame: Each game's players by game id. A game
    ///   whose players didn't load is absent, which leaves it out of the role
    ///   breakdown and, for a Treachery game with a winner, counts it in
    ///   `unknownResults` instead of wins or losses.
    init(games: [Game], playersByGame: [String: [Player]], userId: String) {
        var wins = 0
        var losses = 0
        var unknownResults = 0
        var roleBreakdown: [Role: Int] = [:]

        for game in games {
            let role = playersByGame[game.id]?.first { $0.userId == userId }?.role
            if let role {
                roleBreakdown[role, default: 0] += 1
            }
            switch game.outcome(forUserId: userId, role: role) {
            case .won: wins += 1
            case .lost: losses += 1
            case .unknown: unknownResults += 1
            case .noWinner: break
            }
        }

        self.init(
            totalGames: games.count,
            wins: wins,
            losses: losses,
            unknownResults: unknownResults,
            roleBreakdown: roleBreakdown
        )
    }
}

/// Where the delete-account flow is. One enum rather than Bool flags, so
/// states like "confirming while deleting" cannot be represented.
enum AccountDeletionState: Equatable {
    /// Nothing in progress.
    case idle
    /// The confirmation that explains what gets deleted is on screen.
    case confirming
    /// The request is in flight.
    case deleting
    /// The server deleted the account and this device signed out. The auth
    /// state listener is about to replace this screen with the signed-out one.
    case deleted
    /// The server deleted the account, but signing this device out failed, so
    /// it is still signed in to an account that no longer exists. Only a
    /// successful sign-out leaves this state; nothing returns it to `idle`.
    case signOutFailed
    /// The server did not confirm the deletion. `message` is shown as is;
    /// `isRetryable` says whether retrying right away can help.
    case failed(message: String, isRetryable: Bool)

    /// Whether a confirmed deletion owns the screen: the request is in flight,
    /// or the account is gone and this device is signing out. Nothing can
    /// start, cancel or repeat the deletion meanwhile, and the rest of the
    /// app stays out of reach.
    var isUnderway: Bool {
        switch self {
        case .deleting, .deleted, .signOutFailed: true
        case .idle, .confirming, .failed: false
        }
    }
}

/// Where renaming is. One enum rather than Bool flags, so states like
/// "saving while not editing" cannot be represented.
enum RenameState: Equatable {
    /// The name is shown, not being edited.
    case idle
    /// The name field is open; `ProfileViewModel.editedName` holds the draft.
    case editing
    /// The draft is being saved. The field stays open until the server
    /// answers.
    case saving
    /// The last rename didn't save and the old name stays. `message` says
    /// why, under the name, until the next edit.
    case failed(message: String)
}

@MainActor
final class ProfileViewModel: ObservableObject {

    // MARK: - Published State

    @Published var user: TreacheryUser?
    @Published var gameStats: GameStats?
    /// The name being typed while renaming.
    @Published var editedName = ""
    @Published private(set) var renameState: RenameState = .idle
    @Published var errorMessage: String?
    @Published private(set) var accountDeletionState: AccountDeletionState = .idle

    /// Whether the name field is open, including while its draft is saved.
    var isEditingName: Bool {
        renameState == .editing || renameState == .saving
    }

    var isSavingName: Bool {
        renameState == .saving
    }

    /// Why the last rename didn't save, if it didn't.
    var renameFailureMessage: String? {
        guard case .failed(let message) = renameState else { return nil }
        return message
    }

    // MARK: - Properties

    private var userId: String?
    private let session: SessionEnding
    private let firestoreManager: FirestoreManaging
    private let cloudFunctions: CloudFunctionsProtocol
    private let trackEvent: (String) -> Void

    private static let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "AccountDeletion")
    private static let profileLogger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "Profile")

    // MARK: - Init

    /// - Parameters:
    ///   - session: Ends the signed-in session once the account is deleted.
    ///     In the app this is `AuthViewModel`, the single source of auth state.
    ///   - trackEvent: Records an analytics event by name.
    init(
        session: SessionEnding,
        firestoreManager: FirestoreManaging = FirestoreManager(),
        cloudFunctions: CloudFunctionsProtocol = CloudFunctions(),
        trackEvent: @escaping (String) -> Void = { AnalyticsService.trackEvent($0) }
    ) {
        self.session = session
        self.firestoreManager = firestoreManager
        self.cloudFunctions = cloudFunctions
        self.trackEvent = trackEvent
    }

    /// User-facing text for loading and renaming failures, kept in one place.
    enum ProfileMessage {
        static let loadFailed = String(
            localized: "Check your connection and try again.",
            comment: "Shown under 'Error loading profile' when the profile or its stats failed to load"
        )
        static let renameFailed = String(
            localized: "We couldn't save your new name. Check your connection and try again.",
            comment: "Shown under the display name when renaming failed; the old name is kept"
        )
    }

    // MARK: - Data Loading

    func loadData(userId: String) async {
        self.userId = userId
        errorMessage = nil

        do {
            async let userTask = firestoreManager.getUser(id: userId)
            async let gamesTask = firestoreManager.getFinishedGames(forUserId: userId)

            user = try await userTask
            let games = try await gamesTask

            await calculateStats(games: games)
        } catch {
            Self.profileLogger.error("Loading the profile failed: \(String(describing: error), privacy: .private)")
            errorMessage = ProfileMessage.loadFailed
        }
    }

    // MARK: - Name Editing

    /// Opens the name field with the current name. Ignored while a rename
    /// is being saved.
    func startEditing() {
        guard renameState != .saving else { return }
        editedName = user?.displayName ?? ""
        renameState = .editing
    }

    /// Saves the edited name, writing only `display_name`, and waits for the
    /// server to confirm it. While offline that wait lasts until the
    /// connection returns, and the Save button shows it's still saving.
    /// On failure the old name stays and `renameState` says why.
    func saveName() async {
        guard renameState == .editing, user != nil, let userId else { return }
        let newName = editedName.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { return }
        renameState = .saving

        do {
            try await firestoreManager.updateDisplayName(newName, forUserId: userId)
            user?.displayName = newName
            renameState = .idle
        } catch {
            Self.profileLogger.error("Renaming failed: \(String(describing: error), privacy: .private)")
            renameState = .failed(message: ProfileMessage.renameFailed)
        }
    }

    // MARK: - Account Deletion

    /// User-facing text for deletion failures, kept in one place.
    enum AccountDeletionMessage {
        static let retry = String(
            localized: "We couldn't delete your account. Check your connection and try again.",
            comment: "Shown when deleting the account failed and can be retried"
        )
        static let timedOut = String(
            localized: "Deleting your account is taking longer than expected. Try again to finish.",
            comment: "Shown when the account deletion request timed out; retrying completes it"
        )
        /// Used only if the server's in-game refusal arrives without a message.
        static let inProgressGameFallback = String(
            localized: "You're in a game that's still in progress. You can delete your account once that game ends.",
            comment: "Shown when the account can't be deleted during a live game"
        )
    }

    /// Whether Delete Account can be used: not while a deletion is under way,
    /// and not while a rename is being saved, so the user never sees that
    /// rename fail after their account is gone. (A rename can't bring a
    /// deleted profile back: it is an update, which fails on a missing
    /// document.)
    var canRequestAccountDeletion: Bool {
        !accountDeletionState.isUnderway && renameState != .saving
    }

    /// Opens the confirmation. Ignored while Delete Account can't be used.
    func requestAccountDeletion() {
        guard canRequestAccountDeletion else { return }
        accountDeletionState = .confirming
    }

    /// Closes the confirmation or a failure message without deleting. Never
    /// interrupts a deletion under way, and never leaves `.signOutFailed`:
    /// that account is already gone.
    func cancelAccountDeletion() {
        guard !accountDeletionState.isUnderway else { return }
        accountDeletionState = .idle
    }

    /// Deletes the account on the server, then signs out through the session
    /// so RootView returns to the signed-out screen. The view calls this only
    /// once the user has confirmed (or chosen Try Again); a call made while a
    /// deletion is under way is ignored, so repeat taps never send a second
    /// request.
    func deleteAccount() async {
        guard !accountDeletionState.isUnderway else { return }
        accountDeletionState = .deleting
        // Leave name editing: an unsaved rename is dropped, not left pending
        // underneath a deletion. (No rename can be saving here: Delete
        // Account is unavailable until it finishes.)
        if renameState == .editing {
            renameState = .idle
        }

        do {
            try await cloudFunctions.deleteAccount()
        } catch AccountDeletionError.inProgressGame(let message) {
            let serverMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            accountDeletionState = .failed(
                message: serverMessage.isEmpty ? AccountDeletionMessage.inProgressGameFallback : serverMessage,
                isRetryable: false
            )
            return
        } catch AccountDeletionError.timedOut {
            Self.logger.error("deleteAccount timed out")
            accountDeletionState = .failed(message: AccountDeletionMessage.timedOut, isRetryable: true)
            return
        } catch {
            Self.logger.error("deleteAccount failed: \(error.localizedDescription, privacy: .private)")
            accountDeletionState = .failed(message: AccountDeletionMessage.retry, isRetryable: true)
            return
        }

        trackEvent("account_deleted")
        endSession()
    }

    /// Signs out again after the server deleted the account but the first
    /// sign-out failed. Never calls the server again; ignored in any other
    /// state.
    func retrySignOut() {
        guard accountDeletionState == .signOutFailed else { return }
        endSession()
    }

    private func endSession() {
        do {
            try session.endSession()
            accountDeletionState = .deleted
        } catch {
            Self.logger.error("Sign-out after account deletion failed: \(error.localizedDescription, privacy: .private)")
            accountDeletionState = .signOutFailed
        }
    }

    // MARK: - Stats Calculation

    private func calculateStats(games: [Game]) async {
        guard let userId else { return }
        var playersByGame: [String: [Player]] = [:]

        for game in games {
            do {
                playersByGame[game.id] = try await firestoreManager.getPlayers(gameId: game.id)
            } catch {
                Self.profileLogger.error("Loading players for stats failed: \(String(describing: error), privacy: .private)")
            }
        }

        gameStats = GameStats(games: games, playersByGame: playersByGame, userId: userId)
    }
}
