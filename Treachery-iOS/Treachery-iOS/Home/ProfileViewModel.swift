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

/// What the Profile screen shows once it has loaded: the user's public
/// profile and their stats over finished games. One value, loaded together,
/// so the screen never shows a profile beside stats that are still loading
/// or failed.
struct ProfileOverview {
    var user: TreacheryUser
    let stats: GameStats
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
    /// The last rename didn't save and the old name stays. The error says
    /// why, under the name, until the next edit.
    case failed(UserFacingError)
}

/// Where signing out is. Email and phone accounts sign out at once; a guest
/// confirms first, because a guest account can't be signed back into.
enum SignOutState: Equatable {
    /// Nothing in progress.
    case idle
    /// A guest asked to sign out, and the warning that the account will be
    /// lost for good is on screen.
    case confirmingGuestSignOut
    /// Signing out failed and this device is still signed in.
    case failed(UserFacingError)
}

@MainActor
final class ProfileViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var overview: Loadable<ProfileOverview, UserFacingError> = .idle
    /// The name being typed while renaming.
    @Published var editedName = ""
    @Published private(set) var renameState: RenameState = .idle
    @Published private(set) var signOutState: SignOutState = .idle
    @Published private(set) var accountDeletionState: AccountDeletionState = .idle

    /// The profile shown, if one has loaded.
    var user: TreacheryUser? {
        overview.value?.user
    }

    /// Whether the name field is open, including while its draft is saved.
    var isEditingName: Bool {
        renameState == .editing || renameState == .saving
    }

    var isSavingName: Bool {
        renameState == .saving
    }

    /// Why the last rename didn't save, if it didn't.
    var renameFailureMessage: String? {
        guard case .failed(let error) = renameState else { return nil }
        return String(
            localized: "Your new name wasn't saved. \(error.message)",
            comment: "Shown under the display name when renaming failed; the old name is kept. The argument says why."
        )
    }

    /// Why signing out failed, if it did.
    var signOutFailureMessage: String? {
        guard case .failed(let error) = signOutState else { return nil }
        return String(
            localized: "Couldn't sign out. \(error.message)",
            comment: "Shown under Sign Out when signing out failed. The argument says why."
        )
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
    ///   - session: Ends the signed-in session, for Sign Out and once the
    ///     account is deleted, and says whether it is a guest's. In the app
    ///     this is `AuthViewModel`, the single source of auth state.
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

    // MARK: - Data Loading

    /// A profile that is missing or can't be read: `getUser` returns nil for
    /// it. Signing in creates or repairs it, so trying again can help.
    private struct ProfileUnavailable: Error {}

    /// Loads the profile and the stats over the user's finished games
    /// together. What's already shown stays while this runs and if it fails.
    func loadData(userId: String) async {
        self.userId = userId
        overview.startLoading()

        do {
            async let userTask = firestoreManager.getUser(id: userId)
            async let gamesTask = firestoreManager.getFinishedGames(forUserId: userId)

            guard let user = try await userTask else { throw ProfileUnavailable() }
            let games = try await gamesTask
            let playersByGame = await firestoreManager.playersByGame(for: games)

            overview = .loaded(ProfileOverview(
                user: user,
                stats: GameStats(games: games, playersByGame: playersByGame, userId: userId)
            ))
        } catch {
            Self.profileLogger.error("Loading the profile failed: \(String(describing: error), privacy: .private)")
            overview.fail(with: UserFacingError(error))
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
            overview.updateValue { $0.user.displayName = newName }
            renameState = .idle
        } catch {
            Self.profileLogger.error("Renaming failed: \(String(describing: error), privacy: .private)")
            renameState = .failed(UserFacingError(error))
        }
    }

    // MARK: - Sign Out

    /// The Sign Out button's action. An email or phone account signs out at
    /// once; a guest is asked to confirm first. Ignored while the account is
    /// being deleted, which signs out on its own.
    func requestSignOut() {
        guard !accountDeletionState.isUnderway else { return }
        if session.isGuest {
            signOutState = .confirmingGuestSignOut
        } else {
            endSessionForSignOut()
        }
    }

    /// Signs a guest out once they've confirmed losing the account: the
    /// confirmation's Sign Out button calls this. It doesn't require the
    /// confirmation to still be showing, because SwiftUI may close it, which
    /// cancels, before running the button's action. Ignored while the account
    /// is being deleted.
    func confirmGuestSignOut() {
        guard !accountDeletionState.isUnderway else { return }
        endSessionForSignOut()
    }

    /// Closes the guest's confirmation without signing out.
    func cancelSignOut() {
        guard signOutState == .confirmingGuestSignOut else { return }
        signOutState = .idle
    }

    /// On success the auth state listener replaces this screen with the
    /// signed-out one.
    private func endSessionForSignOut() {
        do {
            try session.endSession()
            signOutState = .idle
        } catch {
            Self.profileLogger.error("Signing out failed: \(String(describing: error), privacy: .private)")
            signOutState = .failed(UserFacingError(error))
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
}
