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

    /// The user's public profile.
    @Published private(set) var profile: Loadable<TreacheryUser, UserFacingError> = .idle
    /// The user's stats over their finished games. They load with the
    /// profile but can fail on their own, so a cached profile still shows
    /// when the games aren't cached.
    @Published private(set) var stats: Loadable<GameStats, UserFacingError> = .idle
    /// The name being typed while renaming.
    @Published var editedName = ""
    @Published private(set) var renameState: RenameState = .idle
    @Published private(set) var signOutState: SignOutState = .idle
    @Published private(set) var accountDeletionState: AccountDeletionState = .idle

    /// The profile shown, if one has loaded.
    var user: TreacheryUser? {
        profile.value
    }

    /// Why the profile didn't load, if it didn't, as its failure card says
    /// it. While the profile setup is on hold after a deletion whose outcome
    /// is unknown, a profile that isn't set up says so rather than blame the
    /// connection (`UserFacingError.whileProfileSetup(is:)`).
    var profileFailureShown: UserFacingError? {
        profile.failure?.whileProfileSetup(is: profileSetupState())
    }

    /// Why the stats didn't load, if they didn't. Offline with no finished
    /// games cached, the usual reason, that's said plainly.
    var statsFailureMessage: String? {
        guard let failure = stats.failure else { return nil }
        switch failure {
        case .offline, .serverUnreachable:
            return String(
                localized: "Stats need a connection. Try again when you're back online.",
                comment: "Shown on the stats card when the stats couldn't load because the server couldn't be reached"
            )
        default:
            return String(
                localized: "Your stats didn't load. \(failure.message)",
                comment: "Shown on the stats card when the stats couldn't load. The argument says why."
            )
        }
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
    /// Numbers the loads, so one can tell whether a newer one started while
    /// it ran (`loadData(userId:)`).
    private var newestLoad = 0
    /// Where Try Again is (`retry(userId:)`). The loads read it, so the
    /// screen shows it's loading for as long as Try Again waits for the
    /// profile setup, even if it reappears meanwhile.
    private var retryPhase = RetryPhase.idle
    private let session: SessionEnding
    private let retryProfileSetup: () async -> Void
    private let profileSetupState: () -> ProfileSetupState
    private let firestoreManager: FirestoreManaging
    private let cloudFunctions: CloudFunctionsProtocol
    private let trackEvent: (String) -> Void
    private let announce: @MainActor (String) -> Void

    private static let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "AccountDeletion")
    private static let profileLogger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "Profile")

    // MARK: - Init

    /// - Parameters:
    ///   - session: Ends the signed-in session, for Sign Out and once the
    ///     account is deleted, says whether it is a guest's, and holds back
    ///     setting up the profile while the account is being deleted. In the
    ///     app this is `AuthViewModel`, the single source of auth state.
    ///   - retryProfileSetup: Gives a postponed profile setup another go and
    ///     returns once it's over, so Try Again can find a profile that
    ///     couldn't be created at sign-in. While the setup is on hold after
    ///     a deletion (`ProfileSetupState.onHoldUntilRelaunch`), it only
    ///     checks whether the account is gone. In the app this is
    ///     `AuthViewModel.retryProfileSetup()`.
    ///   - profileSetupState: How far the profile setup has got, read
    ///     whenever the screen shows a failure (`profileFailureShown`). In
    ///     the app this is `AuthViewModel.profileSetupState`; ProfileView
    ///     observes that view model too, so it shows a change at once.
    ///   - trackEvent: Records an analytics event by name.
    ///   - announce: Says a message to VoiceOver.
    init(
        session: SessionEnding,
        retryProfileSetup: @escaping () async -> Void,
        profileSetupState: @escaping () -> ProfileSetupState,
        firestoreManager: FirestoreManaging = FirestoreManager(),
        cloudFunctions: CloudFunctionsProtocol = CloudFunctions(),
        trackEvent: @escaping (String) -> Void = { AnalyticsService.trackEvent($0) },
        announce: @escaping @MainActor (String) -> Void = { FailureMessage.announce($0) }
    ) {
        self.session = session
        self.retryProfileSetup = retryProfileSetup
        self.profileSetupState = profileSetupState
        self.firestoreManager = firestoreManager
        self.cloudFunctions = cloudFunctions
        self.trackEvent = trackEvent
        self.announce = announce
    }

    // MARK: - Data Loading

    /// Loads the profile and the stats over the user's finished games side by
    /// side, and shows them together. Each fails on its own: offline with no
    /// finished games cached, the cached profile still shows and only the
    /// stats say why they're missing, since stale beats blank. What's
    /// already shown stays while this runs and if it fails. A profile that
    /// is missing or can't be read fails, rather than leave a spinner running.
    /// Only the newest load shows what it read: one that a newer load
    /// overtook ends without changing anything. While Try Again waits for
    /// the profile setup, no load starts or shows what it read: the screen
    /// shows it's loading until Try Again's own load (`retry(userId:)`).
    func loadData(userId: String) async {
        // It would read before the setup is over.
        guard retryPhase == .idle else { return }
        self.userId = userId
        newestLoad += 1
        let load = newestLoad
        profile.startLoading()
        stats.startLoading()

        async let userRead = firestoreManager.getUser(id: userId)
        async let gamesRead = firestoreManager.getFinishedGames(forUserId: userId)

        let profileResult: Result<TreacheryUser, UserFacingError>
        do {
            guard let user = try await userRead else { throw FirestoreReadError.profileUnavailable }
            profileResult = .success(user)
        } catch {
            Self.profileLogger.error("Loading the profile failed: \(String(describing: error), privacy: .private)")
            profileResult = .failure(UserFacingError(error))
        }

        let statsResult: Result<GameStats, UserFacingError>
        do {
            let games = try await gamesRead
            let playersByGame = await firestoreManager.playersByGame(for: games)
            statsResult = .success(GameStats(games: games, playersByGame: playersByGame, userId: userId))
        } catch {
            Self.profileLogger.error("Loading the stats failed: \(String(describing: error), privacy: .private)")
            statsResult = .failure(UserFacingError(error))
        }

        // Try Again's load, say, can still be on its way when the name
        // prompt closes and a newer one starts; it read the placeholder name.
        // And a load that was reading when Try Again was tapped read before
        // the setup.
        guard load == newestLoad, retryPhase == .idle else { return }
        switch profileResult {
        case .success(let user): profile = .loaded(user)
        case .failure(let failure): profile.fail(with: failure)
        }
        switch statsResult {
        case .success(let loaded): stats = .loaded(loaded)
        case .failure(let failure): stats.fail(with: failure)
        }
    }

    /// Try Again after a failed load. A profile that couldn't be set up at
    /// sign-in (offline, say) is set up first; without it there's nothing
    /// to load. That can take a while, about 10 seconds or until the
    /// connection is back, so the screen shows it's loading from the tap,
    /// even if it reappears meanwhile, and another tap while it waits is
    /// ignored. A retry whose task is cancelled stops waiting and loads
    /// nothing. While the setup is on hold after a deletion
    /// (`ProfileSetupState.onHoldUntilRelaunch`), Try Again only checks
    /// whether the account is gone before it loads; see
    /// `AuthViewModel.retryProfileSetup()`.
    func retry(userId: String) async {
        guard retryPhase == .idle else { return }
        retryPhase = .waitingForProfileSetup
        profile.startLoading()
        stats.startLoading()
        await retryProfileSetup()
        retryPhase = .idle
        guard !Task.isCancelled else { return }
        await loadData(userId: userId)
    }

    /// Where Try Again is. The loads read it: a flag that only Try Again
    /// checked let a load started while it waited, as when the screen
    /// reappeared, bring back the failure, with a Try Again a tap then
    /// couldn't run.
    private enum RetryPhase {
        /// Not waiting. Loads run and show what they read as usual, Try
        /// Again's own too: a newer one, as when the name prompt closes,
        /// still overtakes it.
        case idle
        /// Waiting for the profile setup's attempt or, while the setup is on
        /// hold after a deletion (`ProfileSetupState.onHoldUntilRelaunch`),
        /// for the check of whether the account is gone, with the screen
        /// showing it's loading. Try Again loads once that's over.
        case waitingForProfileSetup
    }

    /// Loads again once the profile setup is finished, which can happen
    /// while this screen is open: when the name prompt over it closes, or
    /// when a retry sets the profile up in the background. What's shown was
    /// read before then, with the placeholder name or before the profile
    /// existed.
    func profileSetupDidChange(to state: ProfileSetupState, userId: String) async {
        guard state == .finished else { return }
        await loadData(userId: userId)
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
            profile.updateValue { $0.displayName = newName }
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
    /// signed-out one. A failure is announced after every attempt: it shows
    /// under Sign Out, away from VoiceOver focus, and a repeated failure
    /// changes nothing on screen.
    private func endSessionForSignOut() {
        do {
            try session.endSession()
            signOutState = .idle
        } catch {
            Self.profileLogger.error("Signing out failed: \(String(describing: error), privacy: .private)")
            signOutState = .failed(UserFacingError(error))
            if let signOutFailureMessage {
                announce(signOutFailureMessage)
            }
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
    /// request. The session holds back setting up the profile meanwhile.
    func deleteAccount() async {
        guard !accountDeletionState.isUnderway else { return }
        accountDeletionState = .deleting
        session.accountDeletionWillStart()
        // Leave name editing: an unsaved rename is dropped, not left pending
        // underneath a deletion. (No rename can be saving here: Delete
        // Account is unavailable until it finishes.)
        if renameState == .editing {
            renameState = .idle
        }

        do {
            try await cloudFunctions.deleteAccount()
        } catch AccountDeletionError.inProgressGame(let message) {
            // The server refuses at deleteAccount's step 1 or 2, before it
            // deletes any of the account, and that run is over.
            let serverMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            failAccountDeletion(
                message: serverMessage.isEmpty ? AccountDeletionMessage.inProgressGameFallback : serverMessage,
                isRetryable: false,
                failure: .nothingDeleted
            )
            return
        } catch AccountDeletionError.notSent {
            // The request never left this device.
            Self.logger.error("deleteAccount wasn't sent")
            failAccountDeletion(message: AccountDeletionMessage.retry, isRetryable: true, failure: .nothingDeleted)
            return
        } catch AccountDeletionError.timedOut {
            // The server may have stopped anywhere, or still be running: with
            // the profile deleted (step 5) and the sign-in account not yet
            // (step 6), a setup attempt would create the profile again.
            Self.logger.error("deleteAccount timed out")
            failAccountDeletion(message: AccountDeletionMessage.timedOut, isRetryable: true, failure: .outcomeUnknown)
            return
        } catch {
            // The request may have reached the server. A run can fail after
            // deleting the profile (at step 6, say), a lost connection can
            // leave it running, and an answer this app doesn't understand
            // (`unexpectedResponse`) can come from one that finished.
            Self.logger.error("deleteAccount failed: \(error.localizedDescription, privacy: .private)")
            failAccountDeletion(message: AccountDeletionMessage.retry, isRetryable: true, failure: .outcomeUnknown)
            return
        }

        trackEvent("account_deleted")
        endSession()
    }

    /// Ends a deletion the server didn't confirm. This device stays signed
    /// in; `failure` tells the session whether it can go on setting up the
    /// profile.
    private func failAccountDeletion(message: String, isRetryable: Bool, failure: AccountDeletionFailure) {
        accountDeletionState = .failed(message: message, isRetryable: isRetryable)
        session.accountDeletionDidFail(failure)
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
