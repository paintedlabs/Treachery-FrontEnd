//
//  ProfileView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import Accessibility
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: ProfileViewModel

    /// `viewModel` is built once, the first time this view is installed.
    init(viewModel: @autoclosure @escaping () -> ProfileViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()
            RadialGradient(
                colors: [
                    Color(hex: "1e1735").opacity(0.6),
                    Color.mtgBackground
                ],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Profile info card
                    VStack(spacing: 0) {
                        MtgSectionHeader(title: "Profile")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        OrnateDivider()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)

                        if let user = viewModel.user {
                            ProfileRow(label: "Display Name", value: viewModel.isEditingName ? nil : user.displayName) {
                                if viewModel.isEditingName {
                                    TextField("Name", text: $viewModel.editedName)
                                        .multilineTextAlignment(.trailing)
                                        .textInputAutocapitalization(.words)
                                        .foregroundStyle(Color.mtgGoldBright)
                                }
                            }

                            // Primary-colored text: mtgError text on this card is
                            // below the 4.5:1 contrast minimum (see DeleteAccountSection).
                            if let renameFailure = viewModel.renameFailureMessage {
                                Label {
                                    Text(renameFailure)
                                } icon: {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Color.mtgError)
                                }
                                .font(.footnote)
                                .foregroundStyle(Color.mtgTextPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 4)
                                .accessibilityElement(children: .combine)
                            }

                            ProfileRow(label: "Member Since") {
                                Text(user.createdAt, style: .date)
                                    .foregroundStyle(Color.mtgTextSecondary)
                            }
                        } else {
                            MtgLoadingView()
                                .padding()
                        }
                    }
                    .mtgCardFrame()

                    // Game stats card
                    VStack(spacing: 0) {
                        MtgSectionHeader(title: "Game Stats")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        OrnateDivider()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)

                        if let stats = viewModel.gameStats {
                            HStack(spacing: 8) {
                                MtgStatBox(value: "\(stats.totalGames)", label: "Games", color: Color.mtgTextPrimary)
                                MtgStatBox(value: "\(stats.wins)", label: "Wins", color: Color.mtgSuccess)
                                MtgStatBox(value: "\(stats.losses)", label: "Losses", color: Color.mtgError)
                                MtgStatBox(value: stats.winRateText, label: "Win %", color: Color.mtgGuardian)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)

                            HStack(spacing: 8) {
                                MtgStatBox(value: "\(viewModel.user?.elo ?? 1500)", label: "ELO", color: Color.mtgGoldBright)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)

                            // Partial stats say so rather than pass for complete ones.
                            if stats.unknownResults > 0 {
                                Text("Results for some games couldn't be loaded, so they're left out of wins, losses and Win %.")
                                    .font(.footnote)
                                    .foregroundStyle(Color.mtgTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 12)
                            }

                            // Role breakdown
                            if !stats.roleBreakdown.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Roles Played")
                                        .font(.caption)
                                        .foregroundStyle(Color.mtgTextSecondary)
                                    ForEach(stats.roleBreakdown.sorted(by: { $0.value > $1.value }), id: \.key) { role, count in
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(role.color)
                                                .frame(width: 8, height: 8)
                                            Text(role.displayName)
                                                .font(.subheadline)
                                                .foregroundStyle(Color.mtgTextPrimary)
                                            Spacer()
                                            Text("\(count)")
                                                .font(.subheadline)
                                                .foregroundStyle(Color.mtgTextSecondary)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                            }

                            NavigationLink {
                                GameHistoryView()
                            } label: {
                                HStack {
                                    Text("View Game History")
                                        .foregroundStyle(Color.mtgGold)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(Color.mtgTextSecondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                        } else {
                            MtgLoadingView(message: "Loading stats...")
                                .padding()
                        }
                    }
                    .mtgCardFrame()

                    // Deck Performance card
                    if let deckStats = viewModel.user?.deckStats, !deckStats.isEmpty {
                        VStack(spacing: 0) {
                            MtgSectionHeader(title: "Deck Performance")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, 8)

                            OrnateDivider()
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)

                            ForEach(deckStats.sorted(by: { $0.value.games > $1.value.games }), id: \.key) { deckName, stat in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(deckName)
                                        .font(.system(.subheadline, design: .serif))
                                        .italic()
                                        .foregroundStyle(Color.mtgGoldBright)

                                    HStack(spacing: 16) {
                                        HStack(spacing: 4) {
                                            Text("ELO")
                                                .font(.caption)
                                                .foregroundStyle(Color.mtgTextSecondary)
                                            Text("\(stat.elo)")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Color.mtgGoldBright)
                                        }

                                        HStack(spacing: 4) {
                                            Text("Record")
                                                .font(.caption)
                                                .foregroundStyle(Color.mtgTextSecondary)
                                            Text("\(stat.wins)W - \(stat.losses)L")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Color.mtgTextPrimary)
                                        }

                                        HStack(spacing: 4) {
                                            Text("Games")
                                                .font(.caption)
                                                .foregroundStyle(Color.mtgTextSecondary)
                                            Text("\(stat.games)")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Color.mtgTextPrimary)
                                        }

                                        Spacer()
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }
                        .mtgCardFrame()
                    }

                    // Friends card
                    if viewModel.user != nil {
                        NavigationLink {
                            FriendsListView()
                        } label: {
                            HStack {
                                Text("Friends")
                                    .foregroundStyle(Color.mtgTextPrimary)
                                Spacer()
                                Text("\(viewModel.user?.friendIds.count ?? 0)")
                                    .foregroundStyle(Color.mtgTextSecondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Color.mtgTextSecondary)
                            }
                            .padding(16)
                        }
                        .mtgCardFrame()
                    }

                    // Error
                    if let error = viewModel.errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            MtgErrorBanner(message: "Error loading profile")
                            Text(error)
                                .foregroundStyle(Color.mtgError)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        .padding(16)
                        .mtgCardFrame(borderColor: Color.mtgError)
                    }

                    // Sign out
                    Button("Sign Out") {
                        authViewModel.signOut()
                    }
                    .foregroundStyle(Color.mtgError)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .mtgCardFrame(borderColor: Color.mtgError.opacity(0.5))
                    .accessibilityLabel("Sign out of your account")
                    .disabled(isAccountDeletionUnderway)

                    // Delete account: last, and set apart from the routine actions
                    DeleteAccountSection(
                        isEnabled: viewModel.canRequestAccountDeletion,
                        failureMessage: accountDeletionFailure?.message
                    ) {
                        viewModel.requestAccountDeletion()
                    }
                    .padding(.top, 16)
                }
                .padding()
            }
            .accessibilityHidden(isAccountDeletionUnderway)
        }
        .overlay {
            if isAccountDeletionUnderway {
                AccountDeletionOverlay(state: viewModel.accountDeletionState) {
                    viewModel.retrySignOut()
                }
            }
        }
        // No other tab while the account is being deleted: a lobby created
        // or a friend added meanwhile would outlive the account.
        .toolbarVisibility(isAccountDeletionUnderway ? .hidden : .automatic, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { AnalyticsService.trackScreen("Profile") }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isEditingName {
                    Button(viewModel.isSavingName ? "Saving..." : "Save") {
                        Task { await viewModel.saveName() }
                    }
                    .foregroundStyle(Color.mtgGold)
                    .disabled(viewModel.editedName.isEmpty || viewModel.isSavingName || isAccountDeletionUnderway)
                } else {
                    Button("Edit") {
                        viewModel.startEditing()
                    }
                    .foregroundStyle(Color.mtgGold)
                    .disabled(viewModel.user == nil || isAccountDeletionUnderway)
                }
            }
        }
        .confirmationDialog(
            "Delete Account?",
            isPresented: isConfirmingAccountDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task { await viewModel.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelAccountDeletion()
            }
        } message: {
            Text("""
                This permanently deletes your account, including your profile, friends list and stats. \
                Your name in past games will be replaced with \u{201C}Deleted player\u{201D}. \
                This cannot be undone.
                """)
        }
        // Only for `.failed`: once the server has deleted the account, the
        // overlay above takes over and offers nothing but signing out.
        .alert(
            "Couldn't Delete Account",
            isPresented: isShowingAccountDeletionFailure,
            presenting: accountDeletionFailure
        ) { failure in
            if failure.isRetryable {
                Button("Try Again", role: .destructive) {
                    Task { await viewModel.deleteAccount() }
                }
                Button("Cancel", role: .cancel) {
                    viewModel.cancelAccountDeletion()
                }
            } else {
                Button("OK", role: .cancel) {
                    viewModel.cancelAccountDeletion()
                }
            }
        } message: { failure in
            // Verbatim: for an in-progress game this is the server's own sentence.
            Text(verbatim: failure.message)
        }
        // The failure appears away from the Save button that caused it.
        .onChange(of: viewModel.renameFailureMessage) { _, message in
            if let message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
        .task {
            guard let userId = authViewModel.currentUserId else { return }
            await viewModel.loadData(userId: userId)
        }
    }

    // MARK: - Account Deletion

    private var isAccountDeletionUnderway: Bool {
        viewModel.accountDeletionState.isUnderway
    }

    /// Drives the confirmation from the view model's state. Dismissal only
    /// cancels; it never interrupts a deletion already in flight.
    private var isConfirmingAccountDeletion: Binding<Bool> {
        Binding(
            get: { viewModel.accountDeletionState == .confirming },
            set: { isPresented in
                if !isPresented { viewModel.cancelAccountDeletion() }
            }
        )
    }

    private var accountDeletionFailure: (message: String, isRetryable: Bool)? {
        guard case let .failed(message, isRetryable) = viewModel.accountDeletionState else { return nil }
        return (message, isRetryable)
    }

    private var isShowingAccountDeletionFailure: Binding<Bool> {
        Binding(
            get: { accountDeletionFailure != nil },
            set: { isPresented in
                if !isPresented { viewModel.cancelAccountDeletion() }
            }
        )
    }
}

// MARK: - Delete Account Section

/// The account-deletion entry point: destructive and visually distinct from
/// Sign Out. Below it is a line on what deletion removes or, after a failed
/// attempt, why it failed. The alert says that too, but this line stays on
/// screen even if the alert never appears (a fast failure can arrive while
/// the confirmation is still dismissing).
///
/// A red fill with white text rather than the red-on-surface text Sign Out
/// uses: `mtgError` text on `mtgSurface` measures about 3.4:1, below the
/// 4.5:1 text minimum; white on `mtgError` is about 5.2:1.
private struct DeleteAccountSection: View {
    let isEnabled: Bool
    let failureMessage: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(role: .destructive, action: action) {
                Text("Delete Account")
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.mtgError, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.7)
            .accessibilityHint("Asks you to confirm before anything is deleted.")

            if let failureMessage {
                Label {
                    // Verbatim: for an in-progress game this is the server's own sentence.
                    Text(verbatim: failureMessage)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.mtgError)
                }
                .font(.footnote)
                .foregroundStyle(Color.mtgTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            } else {
                Text("Permanently deletes your account, profile, friends list and stats.")
                    .font(.footnote)
                    .foregroundStyle(Color.mtgTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Account Deletion Overlay

/// Covers the Profile screen from the moment a deletion is confirmed until
/// the signed-out screen replaces it, so nothing else can be started while
/// the request runs. If the account is gone but this device could not sign
/// out, it stays up with signing out as the only way forward.
///
/// Drawn in place rather than presented, so it can't be swiped away or lost
/// to a presentation that is still dismissing.
private struct AccountDeletionOverlay: View {
    let state: AccountDeletionState
    let retrySignOut: () -> Void

    var body: some View {
        ZStack {
            Color.mtgBackground.opacity(0.92)
                .ignoresSafeArea()
            ViewThatFits(in: .vertical) {
                card
                ScrollView { card }
            }
        }
        // Swallows every touch meant for the screen underneath.
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear { announce(state) }
        .onChange(of: state) { _, newState in announce(newState) }
    }

    private var card: some View {
        VStack(spacing: 16) {
            if state == .signOutFailed {
                signOutFailedContent
            } else {
                progressContent
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .mtgCardFrame()
        .padding(24)
    }

    private var progressContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.mtgGold)
            Text(state == .deleted ? "Signing Out\u{2026}" : "Deleting Your Account\u{2026}")
                .font(.headline)
                .foregroundStyle(Color.mtgTextPrimary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var signOutFailedContent: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.largeTitle)
            .foregroundStyle(Color.mtgError)
            .accessibilityHidden(true)
        Text("Couldn't Finish Signing Out")
            .font(.headline)
            .foregroundStyle(Color.mtgTextPrimary)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
        Text("Your account was deleted, but this device is still signed in to it. Sign out to finish.")
            .font(.body)
            .foregroundStyle(Color.mtgTextSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        Button("Sign Out", action: retrySignOut)
            .buttonStyle(MtgPrimaryButtonStyle())
            .accessibilityHint("Signs this device out of the deleted account.")
    }

    /// VoiceOver focus doesn't follow an overlay drawn in place, so say what
    /// happened. `.deleted` needs nothing: the signed-out screen follows at once.
    private func announce(_ state: AccountDeletionState) {
        let announcement: String
        switch state {
        case .deleting:
            announcement = String(localized: "Deleting your account", comment: "VoiceOver announcement while the account is being deleted")
        case .signOutFailed:
            announcement = String(
                localized: "Couldn't finish signing out. Your account was deleted, but this device is still signed in to it.",
                comment: "VoiceOver announcement when the account was deleted but this device couldn't sign out"
            )
        case .idle, .confirming, .deleted, .failed:
            return
        }
        AccessibilityNotification.Announcement(announcement).post()
    }
}

// MARK: - Profile Row

private struct ProfileRow<Content: View>: View {
    let label: String
    var value: String? = nil
    var content: (() -> Content)? = nil

    init(label: String, value: String?, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.value = value
        self.content = content
    }

    init(label: String, value: String) where Content == EmptyView {
        self.label = label
        self.value = value
        self.content = nil
    }

    init(label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.value = nil
        self.content = content
    }

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.mtgTextPrimary)
            Spacer()
            if let value = value {
                Text(value)
                    .foregroundStyle(Color.mtgTextSecondary)
            }
            if let content = content {
                content()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#if DEBUG
#Preview {
    let authViewModel = AuthViewModel()
    NavigationStack {
        ProfileView(viewModel: ProfileViewModel(session: authViewModel))
    }
    .environmentObject(authViewModel)
}
#endif
