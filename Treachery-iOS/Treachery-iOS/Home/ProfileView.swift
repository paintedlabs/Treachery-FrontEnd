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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var viewModel: ProfileViewModel
    @FocusState private var isNameFieldFocused: Bool

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
                    profileContent

                    // Sign Out, About and Delete Account stay reachable even
                    // when the profile can't load. The view model announces
                    // a failed sign-out after every attempt.
                    SignOutSection(
                        isEnabled: !isAccountDeletionUnderway,
                        isGuest: authViewModel.isGuest,
                        failureMessage: viewModel.signOutFailureMessage
                    ) {
                        viewModel.requestSignOut()
                    }
                    .confirmationDialog(
                        "Sign Out of Guest Account?",
                        isPresented: isConfirmingGuestSignOut,
                        titleVisibility: .visible
                    ) {
                        Button("Sign Out", role: .destructive) {
                            viewModel.confirmGuestSignOut()
                        }
                        Button("Cancel", role: .cancel) {
                            viewModel.cancelSignOut()
                        }
                    } message: {
                        Text("""
                            You're playing as a guest, and a guest account can't be signed back into. \
                            If you sign out, your stats, game history and friends are lost for good.
                            """)
                    }

                    AboutSection(version: AppInfo.version(from: Bundle.main.infoDictionary))

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
            // Offline, what's shown may be out of date; this says so.
            .safeAreaInset(edge: .top, spacing: 0) {
                ConnectionBanner()
                    .background(Color.mtgBackground)
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
                        // Nothing more can be typed while the name saves.
                        isNameFieldFocused = false
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
        // VoiceOver doesn't read a failure that appears after its button was
        // tapped (the rename one appears away from Save), so announce it.
        .onChange(of: viewModel.renameFailureMessage) { _, message in
            FailureMessage.announce(message)
        }
        .task { await reload() }
        // The profile setup can finish while this screen is open, as when
        // the name prompt over it closes, and this screen doesn't reappear.
        .onChange(of: authViewModel.profileSetupState) { _, state in
            guard let userId = authViewModel.currentUserId else { return }
            Task { await viewModel.profileSetupDidChange(to: state, userId: userId) }
        }
    }

    private func reload() async {
        guard let userId = authViewModel.currentUserId else { return }
        await viewModel.loadData(userId: userId)
    }

    /// Try Again: sets up a profile that couldn't be at sign-in, then loads.
    private func retry() async {
        guard let userId = authViewModel.currentUserId else { return }
        await viewModel.retry(userId: userId)
    }

    // MARK: - Profile and Stats

    /// The profile only once it's loaded, and a failure with Try Again above
    /// anything kept from an earlier load. The stats card says on its own if
    /// the stats didn't load.
    @ViewBuilder private var profileContent: some View {
        switch viewModel.profile {
        case .idle, .loading(previous: nil):
            MtgLoadingView(message: "Loading profile...")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        case .failed(let failure, let previous):
            LoadFailureCard(title: "Couldn't Load Your Profile", failure: failure) {
                Task { await retry() }
            }
            if let previous {
                profileCards(for: previous)
            }
        case .loading(previous: let user?), .loaded(let user):
            profileCards(for: user)
        }
    }

    @ViewBuilder private func profileCards(for user: TreacheryUser) -> some View {
        profileCard(for: user)
        GameStatsCard(stats: viewModel.stats, failureMessage: viewModel.statsFailureMessage, elo: user.elo) {
            Task { await retry() }
        }
        if let deckStats = user.deckStats, !deckStats.isEmpty {
            DeckPerformanceCard(deckStats: deckStats)
        }
        NavigationLink {
            FriendsListView(retryProfileSetup: { [authViewModel] in await authViewModel.retryProfileSetup() })
        } label: {
            HStack {
                Text("Friends")
                    .foregroundStyle(Color.mtgTextPrimary)
                Spacer()
                Text("\(user.friendIds.count)")
                    .foregroundStyle(Color.mtgTextSecondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.mtgTextSecondary)
            }
            .padding(16)
        }
        .mtgCardFrame()
    }

    private func profileCard(for user: TreacheryUser) -> some View {
        VStack(spacing: 0) {
            MtgSectionHeader(title: "Profile")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            OrnateDivider()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            ProfileRow(label: "Display Name", value: viewModel.isEditingName ? nil : user.displayName) {
                if viewModel.isEditingName {
                    TextField("Name", text: $viewModel.editedName)
                        // Under its label when the row stacks, so aligned with it.
                        .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                        .textInputAutocapitalization(.words)
                        .foregroundStyle(Color.mtgGoldBright)
                        .focused($isNameFieldFocused)
                        // A 44-point target though the text is shorter: a tap
                        // just above or below it focuses the field too.
                        .frame(minHeight: 44)
                        .background {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { isNameFieldFocused = true }
                        }
                        // Locked while the name saves: anything typed then
                        // would be dropped when the save succeeds.
                        .disabled(viewModel.isSavingName)
                        // Edit opens the field ready to type.
                        .onAppear { isNameFieldFocused = true }
                }
            }

            if let renameFailure = viewModel.renameFailureMessage {
                FailureMessage(message: renameFailure)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            ProfileRow(label: "Member Since") {
                Text(user.createdAt, style: .date)
                    .foregroundStyle(Color.mtgTextSecondary)
            }
        }
        .mtgCardFrame()
    }

    // MARK: - Sign Out

    /// Drives the guest's confirmation from the view model's state.
    /// Dismissal only cancels.
    private var isConfirmingGuestSignOut: Binding<Bool> {
        Binding(
            get: { viewModel.signOutState == .confirmingGuestSignOut },
            set: { isPresented in
                if !isPresented { viewModel.cancelSignOut() }
            }
        )
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

// MARK: - Game Stats Card

/// The stats over finished games, which load with the profile but can fail
/// on their own: then the card says why, with Try Again, above any stats
/// kept from an earlier load. The ELO is the profile's, so it always shows.
private struct GameStatsCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let stats: Loadable<GameStats, UserFacingError>
    /// Why the stats didn't load, if they didn't.
    let failureMessage: String?
    let elo: Int
    let retry: () -> Void

    /// Side by side, or one under another at the accessibility text sizes,
    /// where a quarter of the card's width broke their labels mid-word.
    private var resultsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        VStack(spacing: 0) {
            MtgSectionHeader(title: "Game Stats")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            OrnateDivider()
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            if let failureMessage {
                failure(failureMessage)
            }

            if let shown = stats.value {
                results(for: shown)
            } else if stats.failure == nil {
                // Only while the stats load again after failing: the
                // profile and its stats first load together.
                ProgressView()
                    .tint(Color.mtgGold)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.bottom, 8)
                    .accessibilityLabel("Loading stats")
            }

            HStack(spacing: 8) {
                MtgStatBox(value: "\(elo)", label: "ELO", color: Color.mtgGoldBright)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if let shown = stats.value {
                details(for: shown)
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
        }
        .mtgCardFrame()
    }

    /// Why the stats didn't load, and Try Again, on this card only: the
    /// profile above it loaded.
    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FailureMessage(message: message)
            Button("Try Again", action: retry)
                .buttonStyle(MtgSecondaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        // It appears after a load, away from VoiceOver focus, so say it.
        .onAppear { FailureMessage.announce(message) }
    }

    private func results(for stats: GameStats) -> some View {
        resultsLayout {
            MtgStatBox(value: "\(stats.totalGames)", label: "Games", color: Color.mtgTextPrimary)
            MtgStatBox(value: "\(stats.wins)", label: "Wins", color: Color.mtgSuccess)
            MtgStatBox(value: "\(stats.losses)", label: "Losses", color: Color.mtgError)
            MtgStatBox(value: stats.winRateText, label: "Win %", color: Color.mtgGuardian)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder private func details(for stats: GameStats) -> some View {
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
    }
}

// MARK: - Deck Performance Card

private struct DeckPerformanceCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let deckStats: [String: DeckStat]

    /// Side by side, or one under another at the accessibility text sizes,
    /// where a third of the card's width broke the labels mid-word.
    private var statsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 16))
    }

    var body: some View {
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

                    statsLayout {
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .mtgCardFrame()
    }
}

// MARK: - Sign Out Section

/// Sign Out and, if it failed, why (`FailureMessage`). Primary-colored text
/// on a red-bordered card, with the whole card as its target: `mtgError`
/// text on `mtgSurface` is below the 4.5:1 contrast minimum (see
/// DeleteAccountSection).
private struct SignOutSection: View {
    let isEnabled: Bool
    let isGuest: Bool
    let failureMessage: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Text("Sign Out")
                    .foregroundStyle(Color.mtgTextPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .mtgCardFrame(borderColor: Color.mtgError.opacity(0.5))
            .disabled(!isEnabled)
            .accessibilityLabel("Sign out of your account")
            .accessibilityHint(isGuest ? "Asks you to confirm first, because a guest account can't be signed back into." : "")

            if let failureMessage {
                FailureMessage(message: failureMessage)
            }
        }
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
        // Stacked at the accessibility text sizes, where side by side broke
        // the user's own name mid-word.
        AdaptiveRow {
            Text(label)
                .foregroundStyle(Color.mtgTextPrimary)
        } trailing: {
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
        ProfileView(viewModel: ProfileViewModel(session: authViewModel, retryProfileSetup: {}))
    }
    .environmentObject(authViewModel)
}
#endif
