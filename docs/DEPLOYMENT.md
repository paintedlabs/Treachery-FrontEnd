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

## iOS version numbers

The App Store version is `MARKETING_VERSION` on the `Treachery-iOS` target
(Xcode → target → General → Version sets Debug and Release together). The
pipelines only bump the build number, so the version is yours to manage:

1. **Before publishing a release**, bump `MARKETING_VERSION` to the release's
   version in a PR and merge it. A release tagged `v1.3.0` must build version
   `1.3.0`; the App Store lane checks this and stops before building if they
   differ, or if the release's tag isn't `vX.Y.Z`. Release Drafter picks the
   tag from PR labels, so edit the draft's tag if it doesn't match. (Runs
   started by hand from the Actions tab on a branch carry no tag and skip the
   check.)
2. **Right after Apple approves a release**, bump `MARKETING_VERSION` again
   (e.g. `1.3.0` → `1.3.1`) in a PR. App Store Connect rejects uploads whose
   version is not higher than the last approved one, so every TestFlight
   upload from `main` fails until the bump lands.

## iOS phased rollout

Once a version of the app is live, the App Store lane submits each update with
Apple's 7-day phased release: automatic updates reach 1%, 2%, 5%, 10%, 20%,
50% and then 100% of users. App Store Connect offers phased release only for
updates, so the app's first version goes to everyone as soon as it is
approved. The lane asks App Store Connect for a live version before it builds
and logs the answer as "Phased release: on" or "Phased release: off". Phased
release only paces automatic updates; anyone can still download the new
version from the App Store.

Whoever published the release checks Crashlytics (or Xcode Organizer) and
player reports every day of the rollout, and pauses it from the version's
page in App Store Connect when any of these happens:

- crash-free sessions for the new version fall below 99.9%, or a new crash
  hits more than one user;
- a player reports they can't sign in, create or join a lobby, or keep a game
  in sync;
- the Cloud Functions logs show a rise in errors from callables the new
  version uses.

Pauses add up to at most 30 days, and a resumed rollout continues where it
stopped. Fix forward with a new version, or choose "Release to All Users" once
the cause turns out to be harmless.

## iOS crash symbols

The TestFlight and App Store lanes upload each build's dSYMs to Crashlytics
right after building, before anything goes to App Store Connect, so a failed
upload or review submission still leaves Crashlytics with them. A failed
symbol upload never fails the lane; it logs "No dSYMs went to Crashlytics"
with the reason. Each deploy run also keeps the dSYM zip as its
`ios-dsyms-<run id>-<attempt>` artifact for 14 days. To upload it by hand
within that time, from `Treachery-iOS/`:

```bash
# The run id is the number at the end of the run's URL. gh unzips the
# artifact to build/dsyms/Treachery-iOS.app.dSYM.zip.
gh run download <run id> -n ios-dsyms-<run id>-<attempt> -D build/dsyms
# Firebase's uploader comes with the pinned firebase-ios-sdk package.
xcodebuild -resolvePackageDependencies -project Treachery-iOS.xcodeproj \
  -scheme Treachery-iOS -clonedSourcePackagesDirPath build/SourcePackages
build/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols \
  -gsp Treachery-iOS/GoogleService-Info.plist -p ios build/dsyms/Treachery-iOS.app.dSYM.zip
```

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
