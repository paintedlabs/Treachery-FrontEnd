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

## Forcing an iOS update (minimum build)

At launch the iOS app reads one Firestore document, `config/ios`. If the
app's build number is lower than `min_build`, it shows a full-screen
**Update Required** screen in place of the app. Use it to retire a build with
a serious bug, or one that a functions or rules change can no longer support.

It only reaches binaries that contain it: the first App Store build with the
gate, and every build after it. v1.1.0 and earlier never read the document.

**Build numbers, not versions.** `min_build` is compared with the build
number (`CFBundleVersion`); the marketing version is ignored. App Store
Connect shows a build as *version (build)*, so 1.2.0 **(57)** is build 57. CI
numbers each upload one above the latest TestFlight build, whatever its
version, so App Store and TestFlight builds share one sequence, and a minimum
also blocks TestFlight testers on older builds.

### Force an update

**A minimum can lock people out for good.** The gate compares build numbers
and nothing else, and the Update Required screen has no way past it. So
`min_build` must be the build number of an App Store release that the App
Store actually offers to every blocked user, whatever iOS version they run:

- Never use a build that's only on TestFlight, in review or waiting for
  release, even one numbered below the live release. The App Store doesn't
  offer it, so people would need the next release after it, which may not
  be out yet or may not run on their iOS.
- The App Store offers each phone only the releases its iOS can run. So
  before you set it, check that release's minimum iOS version against the
  iOS versions your users run. People on an older iOS than it needs have
  nothing to update to and can never get past the screen.

1. In App Store Connect, open the iOS version that is live on the App Store
   and note its build number. Check its minimum iOS version, which the App
   Store page lists under Compatibility, against the iOS versions people run
   (Firebase Analytics, which the app uses, reports them). If some people
   still run an older iOS than that, use the build number of the newest App
   Store release that supports their iOS instead, unless you mean to lock
   them out. That's the newest version the App Store offers them, as long as
   it's still selected under Pricing and Availability > Last-Compatible
   Version Settings. A TestFlight-only build in between never counts. An
   older release's minimum iOS is `IPHONEOS_DEPLOYMENT_TARGET` in the Xcode
   project at its release tag.
2. In the Firebase console, open Firestore Database > Data. Open the `config`
   collection (start it if it doesn't exist), then the document `ios`.
3. Set the fields:

   | Field | Type | Required | What it does |
   |---|---|---|---|
   | `min_build` | number | yes | Builds below this get the Update Required screen. Example: `57`. |
   | `message` | string | no | Text on the screen. Without it: "This version of Treachery is out of date. Update to the latest version to keep playing." |
   | `store_url` | string | no | The App Store link the **Update** button opens. Without it there's no button, only "Update Treachery from the App Store." |

   The console's default field type is string, so switch `min_build` to
   **number**. (The app also accepts a string of digits, but any other value
   is ignored and blocks no one.)
4. Each phone picks it up the next time the app starts fresh. An app that's
   already open isn't interrupted, and one resumed from the background keeps
   running until it's next launched.

**The App Store URL.** In App Store Connect, open Treachery > App Information
and copy the **Apple ID**, a number. The URL is
`https://apps.apple.com/app/id<Apple ID>`. Or open Treachery in the App Store
on an iPhone, tap Share and copy the link. The app accepts only `https://`,
`itms-apps://` and `itms-appss://` links that name a host, such as
`apps.apple.com`; anything else, `http://` included, hides the button.

### Undo

Set `min_build` to `0`, or delete the field or the whole `config/ios`
document. Anyone already on the Update Required screen gets in the next time
they switch back to the app: while that screen is up, the app re-reads the
document every time it returns to the foreground.

### Check the switch before you need it

Nothing else runs the live read: the unit tests use a stub, and Debug builds
skip the check. So run this once on each release candidate before you submit
it, rather than finding a problem during an incident. It blocks no real user:
every build CI uploads is numbered 2 or higher, and builds from before the
gate ignore the document.

1. Run a Release build of the candidate on a simulator or your phone. In
   Xcode, Product > Profile builds Release. Or set Product > Scheme > Edit
   Scheme > Run > Build Configuration to Release, and set it back afterwards,
   since the scheme is in git. Builds made this way are build 1.
2. In `config/ios`, set `min_build` to `2` (number), and set `store_url` if it
   isn't set yet. If a real minimum is already set, leave it alone: it blocks
   build 1 already.
3. Quit the app from the app switcher and open it again. Check that the
   Update Required screen appears and that **Update** opens Treachery's App
   Store page. Check the button on a phone: a simulator has no App Store
   app, so an `itms-apps://` or `itms-appss://` link opens nothing there.
   On a phone, also turn VoiceOver on and check that focus moves to "Update
   Required" when the screen appears.
4. What switching to another app and back should do depends on step 2:
   - If you set `min_build` to `2`, delete it, then switch to another app
     and back. Treachery should open as normal.
   - If you left a real minimum in place, keep it, and switch to another
     app and back. The Update Required screen should stay up: build 1 is
     still below the minimum, so that's the right result. Don't delete the
     real minimum to make the app open; that would let every build below
     it back in.

### What the gate doesn't stop

The gate replaces the app's screens; it doesn't stop its start-up work. A
blocked build still restores the signed-in session, reads the user's
`users/{uid}` document and creates it if it's missing, sets the Analytics
user ID, and registers for and receives push notifications. So `min_build`
alone can't stop a bad write that a build makes at start-up. To stop one,
pair it with a rules or functions change that rejects the write.

### What the check costs

Every fresh start of a Release build waits for the read before it shows
sign-in or the home screen, for at most 3 seconds. How long it usually takes
depends on the network and hasn't been measured yet. Instruments shows each
check as the `VersionGateCheck` signpost (subsystem `com.Solomon.Treachery-iOS`,
category `VersionGate`), and the app logs each check's outcome and duration
under the same category. Each start costs one document read, and so does
each return to the foreground while the Update Required screen is up.

### When the gate lets people in anyway

The check fails open, so it can't strand anyone on its own. The app goes
ahead when:

- the document or `min_build` is missing, or `min_build` isn't a whole number;
- the read fails, or takes longer than 3 seconds;
- the phone is offline and has never read the document (offline, the app
  uses the last copy it read, so a phone that has seen the minimum usually
  stays blocked);
- the build number isn't a whole number;
- it's a Debug build, which is what Xcode's Run button, the UI tests and the
  screenshot lane build. Debug builds are always build 1, so they skip the
  check.

Local Release builds that didn't go through fastlane are also build 1, so any
`min_build` above 1 blocks them.

`firestore.rules` lets anyone read `config/*`, signed in or not, and no client
write it, so edit it in the console (which has Admin access). That's data,
not rules: the "never edit rules in the console" warning above doesn't apply.

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
