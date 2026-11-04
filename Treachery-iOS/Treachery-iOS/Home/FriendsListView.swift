//
//  FriendsListView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import Accessibility
import SwiftUI

struct FriendsListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: FriendsListViewModel
    @State private var friendToRemove: TreacheryUser?

    /// `viewModel` is built once, the first time this view is installed.
    init(viewModel: @autoclosure @escaping () -> FriendsListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    /// - Parameter retryProfileSetup: Gives a postponed profile setup
    ///   another go: `AuthViewModel.retryProfileSetup()` in the app.
    init(retryProfileSetup: @escaping () async -> Void) {
        self.init(viewModel: FriendsListViewModel(retryProfileSetup: retryProfileSetup))
    }

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    searchCard
                    overviewContent
                }
                .padding()
            }
            // Offline, what's shown may be out of date; this says so.
            .safeAreaInset(edge: .top, spacing: 0) {
                ConnectionBanner()
                    .background(Color.mtgBackground)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .confirmationDialog(
            "Remove Friend?",
            isPresented: Binding(
                get: { friendToRemove != nil },
                set: { if !$0 { friendToRemove = nil } }
            ),
            titleVisibility: .visible,
            presenting: friendToRemove
        ) { friend in
            Button("Remove", role: .destructive) {
                Task { await viewModel.removeFriend(friend) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { friend in
            Text("Remove \(friend.displayName) from your friends? You will be removed from their friends list too.")
        }
        // An alert, because the row that failed can be off screen, and also a
        // line under that row (`actionFailureLine`), because an alert raised
        // while the Remove confirmation is still closing may never appear.
        .alert(
            viewModel.actionFailure?.action.failureTitle ?? "",
            isPresented: isShowingActionFailure,
            presenting: viewModel.actionFailure
        ) { _ in
            Button("OK", role: .cancel) { viewModel.dismissActionFailure() }
        } message: { failure in
            Text(failure.error.message)
        }
        .onChange(of: searchAnnouncement) { _, announcement in
            if let announcement {
                AccessibilityNotification.Announcement(announcement).post()
            }
        }
        .onAppear { AnalyticsService.trackScreen("Friends") }
        .task { await reload() }
        .refreshable { await retry() }
    }

    private var isShowingActionFailure: Binding<Bool> {
        Binding(
            get: { viewModel.actionFailure != nil },
            set: { isPresented in
                if !isPresented { viewModel.dismissActionFailure() }
            }
        )
    }

    private func reload() async {
        guard let userId = authViewModel.currentUserId else { return }
        await viewModel.loadData(userId: userId)
    }

    /// Try Again and pull to refresh: sets up a profile that couldn't be at
    /// sign-in, then loads.
    private func retry() async {
        guard let userId = authViewModel.currentUserId else { return }
        await viewModel.retry(userId: userId)
    }

    // MARK: - Search

    private var searchCard: some View {
        VStack(spacing: 12) {
            MtgSectionHeader(title: "Add Friends")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            OrnateDivider()
                .padding(.horizontal, 16)

            HStack(spacing: 8) {
                TextField("Search by display name", text: $viewModel.searchText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .foregroundStyle(Color.mtgTextPrimary)
                    .background(Color.mtgCardElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.mtgDivider, lineWidth: 1)
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        Task { await viewModel.searchUsers() }
                    }

                if case .loading = viewModel.search {
                    ProgressView()
                        .tint(Color.mtgGold)
                        .frame(minWidth: 44, minHeight: 44)
                } else if !viewModel.searchText.isEmpty {
                    Button {
                        Task { await viewModel.searchUsers() }
                    } label: {
                        Text("Search")
                            .font(.subheadline)
                            .foregroundStyle(Color.mtgGold)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
            .padding(.horizontal, 16)

            searchResults
        }
        .padding(.bottom, 8)
        .mtgCardFrame()
    }

    @ViewBuilder private var searchResults: some View {
        switch viewModel.search {
        case .idle, .loading:
            EmptyView()
        case .loaded(let search) where search.players.isEmpty:
            VStack(alignment: .leading, spacing: 4) {
                Text(noMatchesMessage(for: search))
                    .font(.subheadline)
                    .foregroundStyle(Color.mtgTextPrimary)
                Text("Search matches the start of a name, and capital letters count.")
                    .font(.footnote)
                    .foregroundStyle(Color.mtgTextSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .accessibilityElement(children: .combine)
        case .loaded(let search):
            ForEach(search.players) { user in
                searchResultRow(for: user)
            }
        case .failed(let failure, _):
            FailureMessage(message: searchFailureMessage(failure))
                .padding(.horizontal, 16)
        }
    }

    /// What VoiceOver hears when a search ends without results to explore.
    private var searchAnnouncement: String? {
        switch viewModel.search {
        case .loaded(let search) where search.players.isEmpty:
            noMatchesMessage(for: search)
        case .failed(let failure, _):
            searchFailureMessage(failure)
        case .idle, .loading, .loaded:
            nil
        }
    }

    private func searchFailureMessage(_ failure: UserFacingError) -> String {
        String(
            localized: "Couldn't search for players. \(failure.message)",
            comment: "Shown under the friend search when it failed. The argument says why."
        )
    }

    /// "No players named “Ada”", or "No other players named “Ada”" when only
    /// the signed-in user's own name matched: they're left out of results.
    private func noMatchesMessage(for search: PlayerSearch) -> String {
        if search.matchedSignedInUser {
            String(
                localized: "No other players named \u{201C}\(search.query)\u{201D}",
                comment: "Friend search result when only the user's own name matched. The argument is what they searched for."
            )
        } else {
            String(
                localized: "No players named \u{201C}\(search.query)\u{201D}",
                comment: "Friend search result when no name matched. The argument is what they searched for."
            )
        }
    }

    private func searchResultRow(for user: TreacheryUser) -> some View {
        let target = FriendAction.Target.searchResult(userId: user.id)
        return VStack(spacing: 0) {
            AdaptiveRow {
                Text(user.displayName)
                    .foregroundStyle(Color.mtgTextPrimary)
            } trailing: {
                if viewModel.isFriend(user) {
                    Text("Friends")
                        .font(.caption)
                        .foregroundStyle(Color.mtgSuccess)
                } else if viewModel.sentRequestUserIds.contains(user.id) {
                    Text("Request Sent")
                        .font(.caption)
                        .foregroundStyle(Color.mtgGold)
                } else if let action = viewModel.actionInFlight(on: target) {
                    ActionProgress(action: action)
                } else {
                    Button {
                        Task { await viewModel.sendRequest(to: user) }
                    } label: {
                        CapsuleButtonLabel(title: "Add", style: .filled(Color.mtgGold))
                    }
                    .accessibilityLabel("Send friend request to \(user.displayName)")
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)

            actionFailureLine(on: target)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Friends and Requests

    /// Friends and requests only once they've loaded, "No friends yet" only
    /// when a load succeeded with none, and a failure with Try Again above
    /// anything kept from an earlier load.
    @ViewBuilder private var overviewContent: some View {
        switch viewModel.overview {
        case .idle, .loading(previous: nil):
            friendsCard(friends: nil)
        case .failed(let failure, let previous):
            LoadFailureCard(title: "Couldn't Load Friends", failure: failure) {
                Task { await retry() }
            }
            // What an earlier load found, but never "No friends yet": under
            // a failure it would read as the answer.
            if let previous {
                if !previous.pendingRequests.isEmpty {
                    pendingRequestsCard(previous.pendingRequests)
                }
                if !previous.friends.isEmpty {
                    friendsCard(friends: previous.friends)
                }
            }
        case .loading(previous: let overview?), .loaded(let overview):
            overviewCards(for: overview)
        }
    }

    @ViewBuilder private func overviewCards(for overview: FriendsOverview) -> some View {
        if !overview.pendingRequests.isEmpty {
            pendingRequestsCard(overview.pendingRequests)
        }
        friendsCard(friends: overview.friends)
    }

    private func pendingRequestsCard(_ requests: [FriendRequest]) -> some View {
        VStack(spacing: 0) {
            MtgSectionHeader(title: "Friend Requests (\(requests.count))")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            OrnateDivider()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            ForEach(requests) { request in
                let target = FriendAction.Target.request(id: request.id)
                VStack(spacing: 0) {
                    AdaptiveRow {
                        VStack(alignment: .leading) {
                            Text(request.fromDisplayName)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.mtgTextPrimary)
                            Text("Wants to be friends")
                                .font(.caption)
                                .foregroundStyle(Color.mtgTextSecondary)
                        }
                    } trailing: {
                        if let action = viewModel.actionInFlight(on: target) {
                            ActionProgress(action: action)
                        } else {
                            // The two buttons stack too when even they don't fit side by side.
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) { requestButtons(for: request) }
                                VStack(alignment: .leading, spacing: 0) { requestButtons(for: request) }
                            }
                        }
                    }
                    .padding(.vertical, 8)

                    actionFailureLine(on: target)
                }
                .padding(.horizontal, 16)
            }
        }
        .mtgCardFrame()
    }

    @ViewBuilder private func requestButtons(for request: FriendRequest) -> some View {
        Button {
            Task { await viewModel.acceptRequest(request) }
        } label: {
            CapsuleButtonLabel(title: "Accept", style: .filled(Color.mtgSuccess))
        }
        .accessibilityLabel("Accept friend request from \(request.fromDisplayName)")

        Button {
            Task { await viewModel.declineRequest(request) }
        } label: {
            CapsuleButtonLabel(title: "Decline", style: .outlined(Color.mtgTextSecondary))
        }
        .accessibilityLabel("Decline friend request from \(request.fromDisplayName)")
    }

    /// The friends card. `friends` is nil while the first load runs.
    private func friendsCard(friends: [TreacheryUser]?) -> some View {
        VStack(spacing: 0) {
            MtgSectionHeader(title: friends.map { "Friends (\($0.count))" } ?? "Friends")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            OrnateDivider()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            if let friends {
                if friends.isEmpty {
                    Text("No friends yet. Search for players above.")
                        .foregroundStyle(Color.mtgTextSecondary)
                        .font(.subheadline)
                        .padding(16)
                } else {
                    friendRows(friends)
                }
            } else {
                MtgLoadingView()
                    .padding()
            }
        }
        .mtgCardFrame()
    }

    private func friendRows(_ friends: [TreacheryUser]) -> some View {
        ForEach(friends) { friend in
            let target = FriendAction.Target.friend(userId: friend.id)
            VStack(spacing: 0) {
                AdaptiveRow {
                    Text(friend.displayName)
                        .foregroundStyle(Color.mtgTextPrimary)
                } trailing: {
                    if let action = viewModel.actionInFlight(on: target) {
                        ActionProgress(action: action)
                    } else {
                        Button {
                            friendToRemove = friend
                        } label: {
                            CapsuleButtonLabel(title: "Remove", style: .destructive)
                        }
                        .accessibilityLabel("Remove \(friend.displayName) from friends")
                    }
                }
                .padding(.vertical, 4)

                actionFailureLine(on: target)
            }
            .padding(.horizontal, 16)

            if friend.id != friends.last?.id {
                Rectangle()
                    .fill(Color.mtgDivider)
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Action Failure and Progress

extension FriendsListView {
    /// Why the last action on `target`'s row didn't go through, under the
    /// row, if it didn't. The view model announces it.
    @ViewBuilder fileprivate func actionFailureLine(on target: FriendAction.Target) -> some View {
        if let message = viewModel.actionFailureMessage(on: target) {
            FailureMessage(message: message)
                .padding(.bottom, 8)
        }
    }
}

/// In place of a row's buttons while one of its actions runs: the row can't
/// start another, and says what it's doing.
private struct ActionProgress: View {
    let action: FriendAction

    var body: some View {
        ProgressView()
            .tint(Color.mtgGold)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(label)
    }

    private var label: String {
        switch action {
        case .sendRequest: String(localized: "Sending friend request", comment: "VoiceOver label while a friend request is being sent")
        case .acceptRequest: String(localized: "Accepting friend request", comment: "VoiceOver label while a friend request is being accepted")
        case .declineRequest: String(localized: "Declining friend request", comment: "VoiceOver label while a friend request is being declined")
        case .removeFriend: String(localized: "Removing friend", comment: "VoiceOver label while a friend is being removed")
        }
    }
}

// MARK: - Capsule Button Label

/// The small capsule look of the friend actions, inside a hit area at least
/// 44 points tall: the capsule stays compact, the target doesn't.
private struct CapsuleButtonLabel: View {
    enum Style {
        /// Dark text on a capsule filled with the color.
        case filled(Color)
        /// Text in the color, in a plain outline.
        case outlined(Color)
        /// Light text in a red outline. Red text itself, `mtgError` on these
        /// cards, is below the 4.5:1 contrast minimum.
        case destructive
    }

    /// A resource, not a `String`, so the callers' literals are extracted
    /// and localized.
    let title: LocalizedStringResource
    let style: Style

    var body: some View {
        Group {
            switch style {
            case .filled(let color):
                Text(title)
                    .foregroundStyle(Color.mtgBackground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(color, in: Capsule())
            case .outlined(let color):
                Text(title)
                    .foregroundStyle(color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .overlay(Capsule().stroke(Color.mtgDivider, lineWidth: 1))
            case .destructive:
                Text(title)
                    .foregroundStyle(Color.mtgTextPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .overlay(Capsule().stroke(Color.mtgError, lineWidth: 1))
            }
        }
        .font(.caption)
        // One word: never broken across lines. Rows stack instead (AdaptiveRow).
        .fixedSize()
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - Action Failure Titles

private extension FriendAction {
    var failureTitle: String {
        switch self {
        case .sendRequest: String(localized: "Couldn't Send Friend Request", comment: "Alert title when sending a friend request failed")
        case .acceptRequest: String(localized: "Couldn't Accept Friend Request", comment: "Alert title when accepting a friend request failed")
        case .declineRequest: String(localized: "Couldn't Decline Friend Request", comment: "Alert title when declining a friend request failed")
        case .removeFriend: String(localized: "Couldn't Remove Friend", comment: "Alert title when removing a friend failed")
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        FriendsListView(retryProfileSetup: {})
    }
    .environmentObject(AuthViewModel())
}
#endif
