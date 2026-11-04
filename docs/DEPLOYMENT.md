# Deployment & Environments

## The one thing to internalize first

**Staging and production share a single Firebase project** (`treachery-71922`).
Only *web hosting* is split into two sites; Firestore, Cloud Functions, and
security rules are shared. Consequences:

- A functions or rules change "deployed to staging" is **live for production
  users immediately**. Functions changes must be backward-compatible (new game
  fields optional, absent = old behaviour); rules changes get no staging
  rehearsal, so review them against the `firestore-tests/` suite before merge.
- The staging *web app* is the only truly isolated surface — it's the place to
  test client changes against real Firebase before cutting a release.

| Environment | URL | Updated by |
|---|---|---|
| Production web | [treachery.games](https://treachery.games) | Publishing a GitHub release |
| Staging web | [treachery-staging.web.app](https://treachery-staging.web.app) | Push to `main` |
| Functions / rules / Firestore (shared) | — | Push to `main` |
| iOS TestFlight | — | Push to `main` touching `Treachery-iOS/**` |
| iOS App Store | — | Publishing a GitHub release |
| Android Play internal | — | Push to `main` touching `TreacheryAndroid/**` |
| Android Play production | — | Publishing a GitHub release |

## Workflows (`.github/workflows/`)

| Workflow | Trigger | Deploys |
|---|---|---|
| `ci.yml` | PR to `main` | nothing — gates the merge (web typecheck/lint/build, functions unit + integration, rules suite, Playwright E2E) |
| `deploy-staging.yml` | push to `main` touching `Treachery/**`, `functions/**`, `firebase.json`, `firestore.rules`, `firestore.indexes.json` | staging hosting + **shared** functions, rules, indexes |
| `deploy-web-production.yml` | release published | production hosting + functions |
| `deploy-testflight.yml` | push to `main` touching `Treachery-iOS/**` | TestFlight |
| `deploy-internal-test.yml` | push to `main` touching `TreacheryAndroid/**` | Play internal test |
| `deploy-appstore.yml` / `deploy-playstore.yml` | release published | store production |

Practical implications of the path filters:

- A PR touching only web + functions rolls out to staging on merge and
  triggers **no** native pipelines. This is the standard "staging first" path.
- Touching `Treachery-iOS/**` or `TreacheryAndroid/**` ships builds to
  TestFlight / Play internal on merge — keep native changes out of a PR meant
  for staging-only rollout.
- Docs, tests, and workflow files trigger no deploys.

## Promoting to production

Publish a GitHub release. That single event fans out to production web
hosting, App Store submission, and Play production. There is no partial
promote — cut the release when *all three* clients are ready for what's on
`main`.

## Rules changes

`firestore.rules` in the repo is the source of truth. **Never edit rules in
the Firebase console** — the next deploy from `main` silently overwrites
console edits. The change loop:

1. Edit `firestore.rules`
2. Un-skip the matching test(s) in `firestore-tests/test/` and
   `cd firestore-tests && npm test` (~3s)
3. Merge — the staging workflow deploys rules to the shared project

## Local development

```bash
# Web app against local emulators (auth, firestore, functions):
cd Treachery
npm run web            # expo dev server; set EXPO_PUBLIC_USE_EMULATOR=true

# Or a full emulator-backed built app + 4 signed-in players:
npm run playtest       # see docs/TESTING.md
```

Manual deploys (`firebase deploy ...`) work as a fallback but the workflows
are the normal path; prefer merging to `main` so CI gates the change.

## Scheduled cleanup and its indexes

`cleanupStaleGames` (`functions/src/triggers.js`) runs every hour and deletes
`waiting` and `in_progress` games with no activity for 24 hours, together
with their `players` docs. `finished` games are never touched.

Its queries pair `state ==` with a range filter on `last_activity_at` or
`created_at`, so each needs a composite index from `firestore.indexes.json`:
`games (state, last_activity_at)` and `games (state, created_at)`. The
staging workflow deploys them along with the functions. The emulator never
enforces indexes, so a missing one fails only in the real project;
`npm test` in `functions/` checks that both are declared.

**First deploy with the indexes (November 2026).** They were never declared
before, so every run failed with `FAILED_PRECONDITION` and nothing has been
swept since the job shipped in March 2026. After that deploy:

1. The indexes build for a few minutes (Firebase console → Firestore →
   Indexes shows them as *Building*). Runs during the build still fail.
2. The next runs purge the backlog since March 2026, oldest first. Each of
   the four queries (two per state) reads at most 100 games per hourly run,
   so one run deletes at most 400 games and a large backlog drains over
   several runs. Finished games are never touched.
3. Confirm in Cloud Logging. In Logs Explorer, filter on
   `resource.type="cloud_run_revision"` and
   `resource.labels.service_name="cleanupstalegames"`. Every run should log
   `cleanupStaleGames: deleted N stale games.`, with N above 0 while the
   backlog drains. A failing query logs
   `cleanupStaleGames: skipped "<state>" games this run:` with the query and
   Firestore's error (for a missing index, a console link that creates it),
   and the run is marked failed; the other state is still swept.
