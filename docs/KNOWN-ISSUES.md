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
| Every user doc world-readable: `email`, `phone_number`, `fcm_token` exposed to any signed-in user. Needs PII split into an owner-only subcollection — rules cannot withhold individual fields | **fixed** — public profile + `users/{uid}/private/data`; FCM via `registerFcmToken` |
| Non-participants can inject themselves into `player_ids` of an `in_progress` game, then read every player's hidden role/identity | **fixed — #97** |
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
| `Alert.alert` is a no-op on react-native-web: forgot-password confirmation and lobby "Copied!" never show; forgot-password also reads a stale error closure and reports success on failure | **open** |

## Lower severity

Not all individually test-encoded; from the audit report.

- Profile win-rate deflated (divides by games with no recorded winner)
- `max_players` mismatch: create screen writes 12 for non-treachery, settings/server cap at 8, bricking the stepper for those games (partially addressed: createGame callable caps at 8)
- Planar die cost displays the previous roller's count, not the caller's actual (often free) cost
- Stale/deleted game link → infinite spinner with the web back button trapped
- Client-side game-code generation is check-then-act racy; duplicate codes make one game unjoinable by code (**fixed** for createGame callable path)
- New-user onboarding skippable via a `createUserDocumentIfNeeded` double-invocation race
- `useConnectionStatus` watches only `navigator.onLine`, never Firestore sync state
- Wearer of Masks X-cost unenforced server-side
- Passwords trimmed before length validation
- Duplicate friend requests after reload (sent-set is session-only)
- N+1 sequential player fetches in history/profile
- `getRoleDistribution` falls back to a sum-4 distribution for 9+ players (latent — reachable only via the rules capacity bypass)

## Repo hygiene

- `functions/node_modules` is committed (~6.9k tracked files), inflating every
  diff and causing spurious conflicts. Untrack with
  `git rm -r --cached functions/node_modules` (safe: all workflows `npm ci`)
- Lobby "Game Mode" chips clip off-screen at phone widths ("Treachery +
  Planechase" unreachable at 375px)
