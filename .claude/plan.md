# Add Firebase Analytics to Native iOS App

## Overview
Mirror the web app's analytics implementation in the native SwiftUI app. FirebaseAnalytics is already an SPM dependency but isn't being used.

## Changes

### 1. Enable analytics in GoogleService-Info.plist
- Set `IS_ANALYTICS_ENABLED` to `true`

### 2. Create `AnalyticsService.swift` (new file in Managers/)
A lightweight wrapper matching the web's `analytics.ts`:
- `trackScreen(_:)` — logs `screen_view` events
- `trackEvent(_:params:)` — logs custom events
- `setUserId(_:)` — sets the analytics user ID
- `setUserProperties(_:)` — sets user properties

### 3. Wire up analytics in existing code (minimal changes)

**Auth — `AuthViewModel.swift`:**
- `listenToAuthState()`: set userId + user properties on auth, clear on sign-out
- `signInAsGuest()`: track `sign_in` with method `guest`
- `signIn(email:password:)`: track `sign_in` with method `email`
- `signUp(email:password:)`: track `sign_up` with method `email`
- `signInWithPhoneCode()`: track `sign_in` with method `phone`
- `signOut()`: track `sign_out`

**Screens — `RootView.swift`:**
- Add `.onAppear` screen tracking for each auth state

**Home — `HomeView.swift`:**
- Track `screen_view` on appear

**Game — `CreateGameView.swift`:**
- Track `create_game` with game_mode + max_players on success

**Game — `GameBoardViewModel.swift`:**
- `unveilCurrentPlayer()`: track `unveil_identity`
- `eliminateAndLeave()`: track `forfeit_game`
- `rollDie()`: track `roll_planar_die` with result
- `endGame()`: track `end_game`

**Other views** (JoinGameView, FriendsListView, LobbyView, etc.):
- Track `join_game`, `send_friend_request`, `accept_friend_request`, `start_game`, `leave_lobby`

This matches the events tracked in the web version exactly.
