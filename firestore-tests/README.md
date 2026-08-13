# firestore-tests

Security-rules tests for the repo-root [`firestore.rules`](../firestore.rules), run against the
Firestore emulator with [`@firebase/rules-unit-testing`](https://firebase.google.com/docs/rules/unit-tests).

These tests exercise the rules only. They do not touch Cloud Functions (which use the Admin SDK and
bypass rules entirely) — see `functions/test/game-logic.test.js` for that layer.

## Running

```bash
cd firestore-tests
npm install
npm test
```

`npm test` runs `scripts/run-rules-tests.js`, which boots the Firestore emulator via
`firebase emulators:exec` and runs mocha inside it. One command, no manual emulator step.

Current state of the suite: **109 passing, 0 skipped**.

### Ports and project id

| | |
|---|---|
| Firestore emulator port | **8098** (this suite owns it; the shared root config uses 8087) |
| Project id | `demo-rules-test` (the Playwright E2E suite uses `demo-test`) |
| Emulator config | `firestore-tests/firebase.json` — **not** the shared root `firebase.json` |

Nothing here reads or writes the root `firebase.json`, so this suite can run at the same time as the
web E2E suite and the functions emulator.

### Java

The Firebase emulators require **Java 21+**; `firebase-tools` hard-errors on anything older. Some dev
machines here default to Java 17, so `scripts/run-rules-tests.js` probes for a suitable JDK
(`JAVA_HOME`, then Homebrew `openjdk@*`, then the standard JVM directories) and exports `JAVA_HOME`
before starting the emulator. On CI, where `java` is already 21+, the script is a straight
passthrough. If it can't find one it fails with an actionable message — install a JDK
(`brew install openjdk@23`) or set `JAVA_HOME` yourself.

### Other commands

```bash
npm run test:mocha                       # mocha only; expects an emulator already on 8098
npx mocha test/users.test.js             # a single spec file
npx mocha --grep "friend_ids"            # filter by name
FIRESTORE_DEBUG=1 npm test               # restore the SDK's gRPC logging
```

Expected `PERMISSION_DENIED` errors from every `assertFails` case are silenced by default
(`setLogLevel('silent')` in `test/setup.js`) so the mocha reporter stays readable.

## Layout

```
firebase.json                 emulator config owned by this project (port 8098)
emulator-bootstrap.rules      deny-all placeholder — NOT the ruleset under test
.mocharc.json                 spec glob, 30s timeout, root-hook registration
scripts/run-rules-tests.js    JDK resolution + `firebase emulators:exec` wrapper
test/helpers.js               test environment, fixture factories, runner rationale
test/setup.js                 mocha root hooks (shared env, clearFirestore between tests)
test/users.test.js            /users/{userId}
test/friend-requests.test.js  /friend_requests/{requestId}
test/games.test.js            /games/{gameId}
test/players.test.js          /games/{gameId}/players/{playerId}
```

`firebase-tools` refuses to reference a rules file outside its own config directory, so
`firebase.json` points at the local `emulator-bootstrap.rules`. The **real** ruleset under test is
read from `../firestore.rules` and pushed into the emulator by `initializeTestEnvironment()` in
`test/helpers.js`. The bootstrap is deny-all on purpose: if that load ever silently fails, the
positive-path tests break loudly instead of passing against the wrong rules.

## Why mocha

`@firebase/rules-unit-testing` is entirely promise-based and needs real `before`/`after` hooks to
boot and tear down a shared `RulesTestEnvironment`, so the monorepo's "plain node script + `assert`"
convention (`functions/test/game-logic.test.js`) doesn't stretch to cover it. Mocha was picked over
vitest because it's the smaller dependency — no vite/esbuild toolchain — runs CommonJS unchanged like
the rest of the repo's node code, and provides the `it.skip` marker the vulnerability tests rely on.
Assertions come from `assertSucceeds` / `assertFails`, so no extra assertion library is needed.

## Test conventions

**Fixtures** are seeded through `withSecurityRulesDisabled` (the `seed()` helper), so setup never
depends on the rules being correct. Assertions then run through `authedDb(uid)` or `anonDb()`, which
are ordinary client contexts subject to the rules. `clearFirestore()` runs after every test.

**Positive-path tests are regression guards.** They lock in the legitimate flows — a host editing
their lobby, a player unveiling themselves, a user creating a friend request — and must never be
skipped. They also pin down the guards that *do* work today, so a future rules rewrite can't quietly
drop them.

## Skip convention

This suite used to keep `it.skip` tests for rules holes that were still open.
Those holes are closed; there are **no skipped tests**. If a new bypass is
found, add a failing `it(...)` on the same branch as the rules fix — do not
assert that insecure behaviour is correct.

Legacy public PII on `users/{uid}` is a **data** problem (`backfill-user-pii.js`),
not a skipped rules test: new writes go to `users/{uid}/private/data`, and the
public doc is world-readable by design for friends search.
