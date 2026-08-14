# Known Issues

Findings from the July 2026 full-codebase audit (six independent review passes
over the web app, Cloud Functions, and Firestore rules, each finding verified
against source — and where marked *reproduced*, against a running emulator).

Most entries are **encoded as skipped tests** that assert the correct
behaviour — see the skip convention in [TESTING.md](TESTING.md). Fixing one
means flipping its marker; the suites below are the authoritative, executable
version of this list. This file is the human-readable index.

Status values: **open**, **fix in review** (PR open), **fixed** (merged —
entries move here then get pruned).

## Security / privacy (Firestore rules)

Reachable by any signed-in user — including anonymous guests — via direct SDK
writes. Encoded in `firestore-tests/`.

| Issue | Status |
|---|---|
| Every user doc world-readable: `email`, `phone_number`, `fcm_token` exposed to any signed-in user. Needs PII split into an owner-only subcollection — rules cannot withhold individual fields | **open — schema fixed, data not migrated.** New writes go to `users/{uid}/private/data` on all three clients and FCM goes via `registerFcmToken`, but every pre-existing doc still holds its `email`/`phone_number`, and `firestore.rules:15` still lets any signed-in user read any `users/{uid}`. Closing it means running `functions/scripts/backfill-user-pii.js --apply` against each project. **Not yet run anywhere.** |
| Non-participants can inject themselves into `player_ids` of an `in_progress` game, then read every player's hidden role/identity | **fixed — #97** |
| **Ghost spectator:** a signed-in user (incl. anonymous guest) reads any waiting game doc, appends their uid to `player_ids` via the append-self rule (no player doc, no join code), stays invisible in every lobby UI (all render the subcollection), and after the deal reads every `role`/`identity_card_id` — the read gate is `uid in player_ids`. Bypasses the join code entirely | **fixed** — `startGame` rebuilds `player_ids` from the seated player docs, evicting any uid without a seat at the moment the data turns sensitive |
| **Ghost spectator**: the append-self join rule requires no player doc, so any signed-in user (incl. anonymous) can add their uid to a *waiting* game's `player_ids`, stay invisible to every lobby UI (all render the subcollection), survive `startGame` (deals from the subcollection only), and
| `player_ids` can be overwritten wholesale (evict the whole table) | **fixed — #97** |
| Join rule enforces no `max_players` capacity | **fixed — #97** |
| Player docs creatable in any game with attacker-chosen `life_total`/`order_id` (rules have no state/membership/capacity check). Needs the host's own client-side create moved server-side before the rule can be denied | **fixed** — player create requires `waiting` + membership; `createGame` callable seats host |
| A victim's `friend_ids` can be wiped by overwrite | **fixed — #97** |
| A one-sided friendship can be forced without an accepted request (residual after #97 — rules can't verify a request exists; needs accept/remove moved into a callable) | **fixed** — cross-user `friend_ids` denied; `acceptFriendRequest` / `removeFriend` callables |

## Critical gameplay (Cloud Functions)

Encoded in `functions/test/integration/callables/`.

| Issue | Status |
|---|---|
| Non-treachery games (Planechase / Life Tracker) auto-finish the moment any player hits 0 life — `checkWinConditions` has no game-mode guard and credits "assassin" on the null-roles fallthrough. *Reproduced* | **fixed** |
| `updateGameSettings` starting-life change **always throws** (read-after-write inside its transaction) and rolls back co-submitted settings. *Reproduced* | **fixed** |
| `resolvePuppetMaster` accepts any card id for any player — no permutation check, no elimination check, no once-per-game guard; can mint a second Leader or hand a team the win. *Reproduced* | **fixed** |
| `resolveMetamorph` never clears the stolen card from its target → duplicate identities in play; no elimination/once-only guard. *Reproduced* | **fixed** |
| `resolveWearerOfMasks` allows copying `traitor_09`, inheriting Puppet Master powers | **fixed** |
| `leaveGame` doesn't renumber seats; next join reuses a live `order_id`, making every `orderBy("order_id")` read non-deterministic (seating, host promotion, win tally). *Reproduced: `0, 2, 2`* | **fixed** |
| `onGameFinished` interpolates user-controlled `commander_name` into a Firestore field path (`deck_stats.${name}`): dots silently fragment stats; `/ ~ * [ ]` throw and abort the **whole game's** ELO batch | **fixed** — sanitize commander keys |

## High-impact UI (web)

Encoded in `Treachery/e2e/` (`test.fixme`) and `KNOWN_BROKEN_INVARIANTS`.

| Issue | Status |
|---|---|
| Game-over screen reveals every hidden identity and is reachable mid-game (eliminated spectator "Leave Game", forfeit, or direct `/game-over/<id>` URL) | **fixed** — gate results on `state === finished`; leave/forfeit no longer mid-game spoils |
| Server-promoted host can't start the game — lobby freezes `isHost` from a navigation param instead of reading `game.host_id` | **fixed** — live `host_id` across web/iOS/Android |
| Near-simultaneous life adjustments silently drop taps (optimistic-delta clearing races the snapshot) | **fixed** — keep unflushed pending across peer snapshots |
| Planechase phenomena unreachable: `resolvePhenomenon` has no UI caller, so Interplanar Tunnel / Spatial Merging / Chaotic Aether park the table | **fixed** (web) — `PhenomenonOverlay`; native already had UI |
| Puppet Master resolver sheet shows all players' hidden cards before redistribution | **fixed** — player names only until resolve |
| `canSeeRole` is a dead prop in `PlayerRow` — the Puppet Master face-down peek never renders | **fixed** |
| `Alert.alert` is a no-op on react-native-web: forgot-password confirmation and lobby "Copied!" never show; forgot-password also reads a stale error closure and reports success on failure | **fixed** — `NoticeDialog`; the disbanded-lobby and unavailable-game alerts deleted as duplicates of their full-screen notices |

## Cross-platform parity

Found reviewing #108, which hardened the server ahead of the clients. Not
test-encoded — no CI job builds Swift or Kotlin (see Repo hygiene).

| Issue | Status |
|---|---|
| `resolveWearerOfMasks` rejects `traitor_07`/`09`/`13` but the pickers still offered them, so a legal-looking pick returned a raw server error | **fixed** — web and iOS filter the same three ids |
| `ability_resolved` (the resolvers' once-per-game guard) was server-only, so Puppet Master's button stayed live after resolving | **fixed (web)** — iOS/Android have no equivalent gate, but Metamorph and Wearer self-heal there because their `identity_card_id` changes |
| The `removeFriend` callable had no caller on any client, leaving every removal one-sided | **fixed at the service layer** — no client has friend-removal UI at all, so nothing reaches it yet |
| iOS `updateUser` encoded the whole model, re-writing legacy PII back onto the public doc | **fixed** — public-field allowlist, matching web and Android |
| **Android has no traitor-ability support whatsoever** — no `resolveMetamorph`/`resolvePuppetMaster`/`resolveWearerOfMasks` in `CloudFunctionsRepository`, no resolver UI. Treachery games are unplayable past an unveil on Android | **fixed** — repository methods, `ability_resolved` gating, `AbilityResolverSheet` mirroring the iOS sheets; 211 unit tests green |
| `maxTraitorRarity` is plumbed through both native clients but never sent (iOS passes `nil`, Android omits it), so the setting is web-only | **open** |
| Both native lobbies fall back to the `navIsHost` nav param before the first game snapshot, so a demoted host briefly still sees host UI. Cosmetic — the server enforces host actions | **open** |

## Lower severity

Not all individually test-encoded; from the audit report.

- Profile win-rate deflated (divides by games with no recorded winner)
- `max_players` mismatch: new games are capped at 8 everywhere now, but games
  already stored with `max_players: 12` are still bricked in **both** stepper
  directions — `+` is disabled at `>= 8` and `-` yields `Math.max(2, 11) = 11`,
  which `updateGameSettings` rejects
- Planar die cost displays the previous roller's count, not the caller's actual (often free) cost
- Stale/deleted game link → infinite spinner with the web back button trapped
- Client-side game-code generation is check-then-act racy; duplicate codes make one game unjoinable by code (**fixed** for createGame callable path)
- New-user onboarding skippable via a `createUserDocumentIfNeeded` double-invocation race
- `useConnectionStatus` watches only `navigator.onLine`, never Firestore sync state
- Wearer of Masks X-cost unenforced server-side; the reveal is also drawn
  client-side, so skip-and-reopen rerolls it (same on web — inherent to the
  client-trust design)
- `resolveWearerOfMasks` lacks the `original_identity_card_id` guard the other
  two resolvers have: a Puppet Master redistribution can hand `traitor_13` to a
  live player, who then unveils into a usable Wearer ability on every client.
  Whether that is a rules bug or legitimate is undecided; if it's a bug, the
  fix belongs server-side
- Passwords trimmed before length validation
- Duplicate friend requests after reload (sent-set is session-only)
- N+1 sequential player fetches in history/profile
- `getRoleDistribution` falls back to a sum-4 distribution for 9+ players (latent — reachable only via the rules capacity bypass)

## Repo hygiene

- ~~CI never compiles iOS or Android~~ — **fixed**: `ci-ios.yml`
  (build-for-testing + mock-only unit tests, UITests excluded so nothing
  touches live Firebase) and `ci-android.yml` (compile + unit tests), both
  path-filtered on PRs to main
- Client `games` create is still permitted by `firestore.rules:69-71` with an
  arbitrary `code`/`max_players`/`game_mode`. The `createGame` callable is
  preferred, not enforced, so the duplicate-join-code race survives for any
  non-callable writer
- `allocateUniqueJoinCode` is check-then-use rather than transactional, and
  codes are never released — uniqueness is best-effort over 12 attempts
- `registerFcmToken` will resurrect a deleted user doc (`set(..., {merge:true})`
  creates the document when absent)
- `AuthKey_*.p8` (an APNs auth key) sits untracked in the repo root. Ignored by
  `*.p8`, so not leaked — but it is a live credential on disk
- `GoogleService-Info.plist` is tracked despite matching `.gitignore`; left that
  way deliberately because the iOS build needs it
- Screenshot capture (`fastlane screenshots`) runs against **production**
  Firebase via real guest auth — `--FASTLANE_SNAPSHOT` is passed but no app code
  reads it. Making it repeatable means honouring that flag and pointing at
  fixtures or the emulator
- Lobby "Game Mode" chips clip off-screen at phone widths ("Treachery +
  Planechase" unreachable at 375px)
- ~~`functions/node_modules` is committed~~ — **fixed**, untracked along with
  `.DS_Store`, `xcuserdata` and the `.firebase` hosting cache
