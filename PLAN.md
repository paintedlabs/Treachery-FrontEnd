# Treachery iOS - Implementation Plan

## Overview
Build a full remote-multiplayer Treachery companion app with real-time game state sync,
identity cards with unveil abilities, game code + friends-based joining.

**Stack:** SwiftUI + Firebase (Auth + Firestore) — no custom backend needed.

---

## Phase 1: Foundation (Models, Navigation, Auth State)

### 1a. Add Firestore SPM dependency
- Add `FirebaseFirestore` to the existing firebase-ios-sdk package in Xcode

### 1b. Data Models (`Models/`)
Create Swift models matching Firestore documents:

- **`TreacheryUser`** — uid, displayName, email, friendIds, createdAt
- **`Game`** — id, code (short joinable code), hostId, state (waiting/inProgress/finished), playerCount, settings, createdAt
- **`Player`** — userId, displayName, role, identityCardId, lifeTotal, isEliminated, isUnveiled, joinedAt
- **`IdentityCard`** — id, name, role (leader/guardian/assassin/traitor), abilityText, unveilCondition, flavorText, imageAssetName
- **`Role`** enum — leader, guardian, assassin, traitor (with display names, colors, win condition text)

### 1c. Identity Card Database (`Resources/IdentityCards.json`)
Bundle a JSON file with all 62 identity cards (13 Leaders, 18 Guardians, 18 Assassins, 13 Traitors) scraped from mtgtreachery.net. Load at app startup via a `CardDatabase` manager.

### 1d. Firestore Service (`Managers/FirestoreManager.swift`)
CRUD operations + real-time listeners for:
- Users collection
- Games collection
- Players subcollection within games

### 1e. Auth State Management
- Refactor `FirebaseManager` to use async/await instead of completion handlers
- Add an `AuthViewModel` as an `@EnvironmentObject` that listens to auth state changes
- Root view switches between Login and Home based on auth state

### 1f. Navigation Architecture
- **`RootView`** — checks auth → shows LoginView or HomeView
- **`LoginView`** — email/password login + sign up (refactored from ContentView)
- **`HomeView`** — main menu: Create Game, Join Game, Friends, Profile

---

## Phase 2: Game Lobby

### 2a. Create Game Flow
- Host picks player count (4-8), starting life total
- Firestore creates a `Game` document with a random 4-character code
- Host enters a `LobbyView` showing the code + waiting player list
- Host's Player document added to subcollection

### 2b. Join Game Flow
- Player enters a game code → Firestore query finds the game
- Player's document added to players subcollection
- Real-time listener updates lobby for all players

### 2c. Lobby View
- Shows game code (shareable), player list with join status
- Host has a "Start Game" button (enabled when enough players joined)
- Players can leave the lobby

---

## Phase 3: Core Game Play

### 3a. Role Assignment (on game start)
- Host taps "Start Game" → server-side-ish logic (Cloud Function or host-driven):
  - Determine role distribution based on player count (4→1L/1T/2A, 5→1L/1T/2A/1G, etc.)
  - Randomly assign roles to players
  - Randomly pick identity cards (one per role type per player)
  - Write assignments to each Player document (only that player can read their own role)
- Game state changes to `inProgress`

### 3b. Game Board View (`GameView`)
- **Your Identity** section: Shows your secret role + identity card + unveil ability
- **Player List**: All players with life totals, eliminated status
- **Life Tracking**: Tap +/- to adjust any player's life (synced in real-time)
- **Unveil Button**: One-time reveal of your identity (updates Firestore, all players see it)

### 3c. Elimination & Win Detection
- When a player's life hits 0 (or is manually eliminated), mark as eliminated
- Check win conditions after each elimination:
  - Leader eliminated → Assassins win (unless only Traitor remains)
  - All Assassins + Traitor eliminated → Leader + Guardians win
  - Traitor is last standing → Traitor wins
- Show victory screen with role reveals

---

## Phase 4: Identity Cards

### 4a. Card Detail View
- Tappable card that shows full identity card info
- Card name, role type, full ability text, unveil conditions
- Styled to look like an MTG card

### 4b. Unveil Mechanic
- Unveil button with confirmation dialog
- When unveiled: updates player's isUnveiled in Firestore
- All players see the revealed identity
- Display unveil ability text prominently (reminder of the effect)

### 4c. Card Selection (optional game setting)
- Host can choose to use all cards or a curated subset
- Random card assignment respects the chosen card pool

---

## Phase 5: Social Features

### 5a. User Profiles
- Set display name on first login
- Profile view: display name, email, game history count

### 5b. Friends System
- Search users by display name or email
- Send/accept/decline friend requests (stored in Firestore)
- Friends list view

### 5c. Invite Friends to Game
- From lobby, tap "Invite" → select from friends list
- Push notification or in-app notification (stretch goal)

---

## Phase 6: Polish

### 6a. UI/UX
- Dark theme (fits the MTG/treachery vibe)
- Role-specific colors (Leader=gold, Guardian=blue, Assassin=red, Traitor=purple)
- Card animations for unveil
- Loading states, error handling, empty states

### 6b. Edge Cases
- Host disconnects → reassign host or end game
- Player disconnects mid-game → show as offline, allow rejoin
- Game cleanup → auto-delete old games

---

## Firestore Data Structure

```
users/{userId}
  displayName: String
  email: String
  friendIds: [String]
  createdAt: Timestamp

games/{gameId}
  code: String          // "AXRF" — short join code
  hostId: String
  state: String         // "waiting" | "inProgress" | "finished"
  maxPlayers: Int       // 4-8
  startingLife: Int     // default 40
  winningTeam: String?  // set when game ends
  createdAt: Timestamp

games/{gameId}/players/{oderId}
  oderId: String
  oderId: String
  userId: String
  displayName: String
  role: String          // "leader" | "guardian" | "assassin" | "traitor"
  identityCardId: String
  lifeTotal: Int
  isEliminated: Bool
  isUnveiled: Bool
  joinedAt: Timestamp
```

## Firestore Security Rules (important)
- Players can only read their OWN role/identityCardId until they unveil
- All players can read/write life totals
- Only host can start the game / assign roles
- Game code lookups must be efficient (index on `code` field)

---

## File Structure (new files to create)

```
Treachery-iOS/
├── Treachery_iOSApp.swift          (modify)
├── Models/
│   ├── TreacheryUser.swift
│   ├── Game.swift
│   ├── Player.swift
│   ├── IdentityCard.swift
│   └── Role.swift
├── Managers/
│   ├── FirebaseManager.swift       (modify — async/await)
│   ├── FirestoreManager.swift      (new)
│   └── CardDatabase.swift          (new)
├── ViewModels/
│   ├── AuthViewModel.swift         (new — replaces ContentViewModel)
│   ├── HomeViewModel.swift
│   ├── LobbyViewModel.swift
│   └── GameViewModel.swift
├── Views/
│   ├── RootView.swift
│   ├── Auth/
│   │   ├── LoginView.swift
│   │   └── SignUpView.swift
│   ├── Home/
│   │   ├── HomeView.swift
│   │   ├── CreateGameView.swift
│   │   └── JoinGameView.swift
│   ├── Lobby/
│   │   └── LobbyView.swift
│   ├── Game/
│   │   ├── GameView.swift
│   │   ├── PlayerRowView.swift
│   │   ├── IdentityCardView.swift
│   │   └── VictoryView.swift
│   └── Profile/
│       ├── ProfileView.swift
│       └── FriendsListView.swift
├── Resources/
│   └── IdentityCards.json
└── ContentView/                    (delete — replaced by Views/Auth/)
```

---

## Implementation Order

I'll build this in order: Phase 1 → 2 → 3 → 4 → 5 → 6.
Each phase produces a working app increment — we can test and iterate at each stage.

**Phase 1** is the most critical — it sets up the architecture everything else builds on.
