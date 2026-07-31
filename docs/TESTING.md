# Testing

The repo has four automated test layers plus a manual playtest harness. Each
layer exists because the one above it structurally *cannot* catch a class of
bug — that reasoning is worth keeping in mind when deciding where a new test
belongs.

| Layer | Where | Command | Speed | Catches what nothing else can |
|---|---|---|---|---|
| Functions unit | `functions/test/game-logic.test.js` | `cd functions && npm test` | ~2s | Pure logic regressions (fast feedback) |
| Functions integration | `functions/test/integration/callables/` | `cd functions && npm run test:integration` | ~70s | Bugs in the **real** exported callables — the unit suite re-implements the logic it checks, so it validates a copy |
| Firestore rules | `firestore-tests/` | `cd firestore-tests && npm test` | ~3s | Security-rule holes. The Playwright suite drives the UI, which only takes legitimate paths, so a rule permitting a hostile direct SDK write is invisible to it |
| Web E2E + simulation | `Treachery/e2e/` | `cd Treachery && npm run test:e2e` | ~2min | Full-stack behaviour through real browsers, plus randomized multi-player play |

All four run on every PR (`.github/workflows/ci.yml`). The emulator-backed
suites need **Java 21+** — the rules and integration runners auto-detect a JDK,
but `test:e2e` does not:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@23/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"
```

## The skip convention: tests as an executable bug list

Tests for **known, currently-unfixed bugs** are written asserting the *correct*
behaviour and then marked skipped:

- mocha suites: `it.skip` with a `// SKIP: ...` comment naming the finding
- Playwright: `test.fixme` with a `// FIXME: ...` comment
- the simulation harness: flags in `KNOWN_BROKEN_INVARIANTS`
  (`Treachery/e2e/simulation/invariants.ts`)

Fixing a bug means flipping one marker; the test needs no rewrite, and the
skip list doubles as the canonical bug backlog (see
[KNOWN-ISSUES.md](KNOWN-ISSUES.md)). Never write a test that asserts buggy
behaviour is correct, and never delete a skipped test because it fails when
enabled — failing-when-enabled is the point.

Every skip was verified non-vacuous by un-skipping and re-running: exactly the
expected set fails.

## The simulation harness (fuzzer)

`Treachery/e2e/simulation.spec.ts` drives 4–8 real browser contexts making
semi-random *legal* moves, asserting invariants after every action (card
uniqueness, role-follows-card, life arithmetic, one-way elimination, state
monotonicity, winner consistency). CI runs a small pinned-seed set; locally it
becomes a real fuzzer:

```bash
SIM_SEED=random SIM_STEPS=60 SIM_REPEAT=25 npm run test:e2e -- simulation
```

Failures print the seed and move list; replay with `SIM_SEED=<seed>`. If you
fix a bug listed in `KNOWN_BROKEN_INVARIANTS`, flip its flag to `false` so the
fuzzer starts enforcing that invariant again.

## Manual playtesting

```bash
cd Treachery && npm run playtest
```

Asks which format (Treachery / Treachery + Planechase / Planechase / Life
Tracker) and how many players, then opens one real signed-in browser window
per player, already in a started game (against the local emulator —
disposable, no real data), prints who holds which role, and stays interactive
until you dismiss the Playwright Inspector.

Env vars answer questions in advance and skip those prompts —
`PLAYTEST_MODE=none PLAYTEST_PLAYERS=2 npm run playtest` asks nothing.
Additional knobs (never prompted): `PLAYTEST_LIFE`, and `PLAYTEST_START`
(`seeded` = deterministic, player 1 is the Leader; `real` = the actual Start
button; `lobby` = stop before starting — the one for testing lobby settings
with a full table). `npm run playtest:nobuild` skips the ~30s web rebuild if
`dist/` is already an emulator build.

Native browser dialogs (`window.confirm`) are auto-accepted in playground
windows — Playwright silently *cancels* them otherwise, which reads as
buttons doing nothing.

## Known flake

Under heavy machine load, concurrent lobby joins can exceed even the 20s
assertion window in `guestJoinGame` — every `joinGame` call transacts on the
same game doc, so they serialize (~9.5s worst observed for an 8-player join,
with zero function errors). CI's `retries: 1` absorbs it. If it recurs
locally, check what else the machine is doing before suspecting your change;
a quiet-machine rerun has settled it every time so far.
