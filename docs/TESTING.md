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

## iOS app against local emulators

Debug builds of the iOS app can run against the same local emulators as the
web playtest instead of the shared production project. Launch the app with
`-useEmulators` and it:

- configures Firebase with fake options for project `demo-test` instead of
  `GoogleService-Info.plist`, so anything not pointed at an emulator fails
  rather than reaching production;
- points Auth at `localhost:9099`, Firestore at `localhost:8087` (no SSL,
  in-memory cache) and Functions at `localhost:5001`, the ports in the
  repo-root `firebase.json`;
- turns off Analytics, Crashlytics and FCM auto-init. Those switches persist,
  so the next launch without the argument turns them back on, in any build
  (including a TestFlight or App Store build installed over a Debug one).

Emulator sign-ins live in their own keychain item, so they don't touch your
real session. Release builds don't contain this code. The hosted unit tests
always run this way: the app sees the XCTest host and never configures
production (`thisTestHostIsKeptOffProduction` checks what was configured).

One unit test needs a signed test host, so CI skips it; see
[iOS real-keychain test](#ios-real-keychain-test) below.

**1. Start the emulators** the way the web playtest does (Java 21+, see the
top of this doc), from `Treachery/`:

```bash
npx --no-install firebase emulators:start --project=demo-test \
  --only auth,firestore,functions --config=../firebase.json
```

Or run `npm run playtest`: while the Playwright Inspector is paused, the
emulators are up and the browser windows are already in a game.

**2. Launch the app with the argument.** In Xcode, Product > Scheme > Edit
Scheme > Run > Arguments, add `-useEmulators` under Arguments Passed On Launch,
and untick it when you want production again. From the command line, with
the app installed on a booted simulator:

```bash
xcrun simctl launch <simulator-udid> com.Solomon.Treachery-iOS -useEmulators
```

The console logs "Using the local Firebase emulators for project demo-test".

**3. Play across clients.** The web app in emulator mode
(`EXPO_PUBLIC_USE_EMULATOR=true npm run web`, or the playtest windows) uses
the same `demo-test` project, so iOS and web can create and join the same
games by code.

Limits: push notifications don't work (FCM isn't emulated). Phone sign-in
uses the Auth emulator's fake codes, which it prints in its log; the
simulator skips app verification, so no reCAPTCHA page opens. A physical
device can't reach your Mac's `localhost`, so use a simulator. Use a build
Xcode signed (any normal Run): a `CODE_SIGNING_ALLOWED=NO` build, like CI's,
has no keychain access, so Firebase Auth can't keep anyone signed in.

## iOS real-keychain test

`FirebaseAuthKeychainMigrationTests/movedItemIsFoundByFirebaseAuthsOwnQuery`
is the only test that moves a signed-in session through the real keychain
and reads it back with FirebaseAuth's own query. The other migration tests
use an in-memory keychain, so they can't catch a SecItem query that matches
too much. The test needs a host app with an application identifier, which an
unsigned build doesn't have, so it skips itself there. CI (`ci-ios.yml`) and
any other `CODE_SIGNING_ALLOWED=NO` build report it as skipped.

**Run it by hand once on every release candidate**, on a simulator with an
ad hoc signed host. That needs no Apple account, certificate or provisioning
profile. From `Treachery-iOS/`:

```bash
UDID=<simulator-udid>   # from: xcrun simctl list devices available
DD="$TMPDIR/treachery-keychain-test"

xcodebuild build-for-testing \
  -project Treachery-iOS.xcodeproj -scheme Treachery-iOS \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DD" \
  CODE_SIGN_IDENTITY=-

xcodebuild test-without-building \
  -project Treachery-iOS.xcodeproj -scheme Treachery-iOS \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DD" \
  -only-testing:Treachery-iOSTests/FirebaseAuthKeychainMigrationTests
```

- `CODE_SIGN_IDENTITY=-` signs the simulator build ad hoc (the build log shows
  `Signing Identity: "Sign to Run Locally"`), which gives the host its
  application identifier. Don't add `-allowProvisioningUpdates`: nothing here
  needs the developer account.
- Keep the `-only-testing` filter. The scheme's test action also runs the UI
  tests, which use production; for the same reason, don't use Cmd-U.
- It passed only if the output says
  `Test case 'FirebaseAuthKeychainMigrationTests/movedItemIsFoundByFirebaseAuthsOwnQuery()' passed`.
  `skipped` means the host wasn't signed, and the run proved nothing.

## Known flake

Under heavy machine load, concurrent lobby joins can exceed even the 20s
assertion window in `guestJoinGame` — every `joinGame` call transacts on the
same game doc, so they serialize (~9.5s worst observed for an 8-player join,
with zero function errors). CI's `retries: 1` absorbs it. If it recurs
locally, check what else the machine is doing before suspecting your change;
a quiet-machine rerun has settled it every time so far.
