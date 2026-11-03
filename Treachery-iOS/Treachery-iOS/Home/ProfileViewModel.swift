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
    let roleBreakdown: [Role: Int]

    var winRateText: String {
        guard totalGames > 0 else { return "--" }
        let rate = Double(wins) / Double(totalGames) * 100
        return "\(Int(rate))%"
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

@MainActor
final class ProfileViewModel: ObservableObject {

    // MARK: - Published State

    @Published var user: TreacheryUser?
    @Published var gameStats: GameStats?
    @Published var editedName = ""
    @Published var isEditingName = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published private(set) var accountDeletionState: AccountDeletionState = .idle

    // MARK: - Properties

    private var userId: String?
    private let session: SessionEnding
    private let firestoreManager: FirestoreManaging
    private let cloudFunctions: CloudFunctionsProtocol
    private let trackEvent: (String) -> Void

    private static let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "AccountDeletion")

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
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Name Editing

    func startEditing() {
        editedName = user?.displayName ?? ""
        isEditingName = true
    }

    func saveName() async {
        guard var updatedUser = user, userId != nil else { return }
        guard !editedName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSaving = true
        errorMessage = nil

        updatedUser.displayName = editedName.trimmingCharacters(in: .whitespaces)
        do {
            try await firestoreManager.updateUser(updatedUser)
            user = updatedUser
            isEditingName = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
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
    /// and not while a rename is being saved, which could land after the
    /// server's delete and recreate the profile.
    var canRequestAccountDeletion: Bool {
        !accountDeletionState.isUnderway && !isSaving
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
        // underneath a deletion.
        isEditingName = false

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
        var wins = 0
        var losses = 0
        var roleBreakdown: [Role: Int] = [:]

        for game in games {
            if let players = try? await firestoreManager.getPlayers(gameId: game.id),
               let myPlayer = players.first(where: { $0.userId == userId }),
               let myRole = myPlayer.role {

                roleBreakdown[myRole, default: 0] += 1

                if let winTeamString = game.winningTeam,
                   let winRole = Role(rawValue: winTeamString) {
                    let didWin: Bool
                    if winRole == .leader {
                        didWin = myRole == .leader || myRole == .guardian
                    } else {
                        didWin = myRole == winRole
                    }
                    if didWin {
                        wins += 1
                    } else {
                        losses += 1
                    }
                }
            }
        }

        gameStats = GameStats(
            totalGames: games.count,
            wins: wins,
            losses: losses,
            roleBreakdown: roleBreakdown
        )
    }
}
