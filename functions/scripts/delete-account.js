#!/usr/bin/env node
/**
 * delete-account.js — delete one account at its owner's request, the way the
 * iPhone app's Delete Account does.
 *
 * The web and Android apps can't delete accounts yet, so the privacy policy
 * and the support page offer deletion by email: we reply with a short code,
 * the requester sets it as their display name in Profile, and we delete the
 * account. This script does the deleting. It runs deleteAccountFor
 * (src/callables/account.js), the steps the deleteAccount callable runs for
 * its caller, for the account named on the command line:
 *
 *   1. refuse while the account is in, or hosts, a game in progress
 *   2. leave its waiting lobbies (the next seat becomes host)
 *   3. rename its seats in other games "Deleted player"
 *   4. take it off friends' lists and delete its friend requests
 *   5. delete users/{uid} and everything under it (private/data)
 *   6. delete the sign-in account
 *
 * It refuses unless the profile's display_name is exactly the code given as
 * --expect-name. That is the policy's check that the requester owns the
 * account, and it guards against a mistyped uid. The one exception is a uid
 * with neither a sign-in account nor a profile, only documents still under
 * users/{uid}, which a deletion that stopped in step 5 can leave: no account
 * is left to protect, so --apply by --uid deletes those without checking the
 * name.
 *
 * DRY RUN BY DEFAULT — it reads and reports, and writes nothing at all until
 * you pass --apply. It prints the account (email and phone masked) and what
 * deleting it would do.
 *
 *   Dry run (default):
 *     cd functions && node scripts/delete-account.js --email <address> \
 *       --expect-name <code> --project <project-id>
 *
 *   Apply (only with --project), by the uid the dry run printed:
 *     cd functions && node scripts/delete-account.js --uid <uid> \
 *       --expect-name <code> --apply --project <project-id>
 *
 *   Rehearse against the emulators (no real data touched), with them started
 *   on the integration suite's ports:
 *     FIRESTORE_EMULATOR_HOST=127.0.0.1:8288 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9299 \
 *       node scripts/delete-account.js --uid <uid> --expect-name <code> \
 *       --apply --project demo-test
 *
 * `npm run test:integration` rehearses it on seeded data every time
 * (test/integration/callables/delete-account-script.test.js).
 * docs/ACCOUNT-DELETION.md is the runbook, from the request to the reply.
 *
 * Exit status:
 *   0  deleted, or a dry run that found nothing to refuse
 *   1  refused: no such account, a display name that isn't the code, or a
 *      game in progress
 *   2  usage error, including --apply without --project
 *   3  failed: Firestore or Auth reported an error. Fix what it names and run
 *      the same command again: every step is safe to repeat.
 *
 * Running it again after a successful --apply finds no such account (exit 1)
 * and changes nothing. A web or Android app still signed in to the account
 * can recreate its profile for up to an hour after the deletion, though, and
 * --email and --phone can't see that profile, so check an hour later with
 * --uid (docs/ACCOUNT-DELETION.md).
 *
 * Before it reads anything it prints the project, where that id came from,
 * and whether Firestore and Auth are emulators or live. --apply writes only
 * to a project named with --project, never to one it would only find in
 * GOOGLE_CLOUD_PROJECT, GCLOUD_PROJECT or Application Default Credentials. A
 * dry run may take the project from those. FIRESTORE_EMULATOR_HOST and
 * FIREBASE_AUTH_EMULATOR_HOST must be set together: with only one of them, a
 * run would delete from an emulator and from a live project at once.
 *
 * Credentials come from the usual Application Default Credentials
 * (GOOGLE_APPLICATION_CREDENTIALS or `gcloud auth application-default login`);
 * on the emulators they are not needed. With your own Google account's
 * credentials, Firebase Auth also needs a quota project:
 * `gcloud auth application-default set-quota-project <project-id>`.
 */

const { initializeApp } = require("firebase-admin/app");
const { HttpsError } = require("firebase-functions/v2/https");
const { resolveTarget, describeTarget } = require("./lib/target");

const EXIT_DONE = 0;
const EXIT_REFUSED = 1;
const EXIT_USAGE = 2;
const EXIT_FAILED = 3;

const MAX_LISTED = 10; // paths printed per line of the plan

// The options that take a value, and the field of `opts` each one sets.
const VALUE_OPTIONS = new Map([
  ["--uid", "uid"],
  ["--email", "email"],
  ["--phone", "phone"],
  ["--expect-name", "expectName"],
  ["--project", "projectId"],
]);

// Admin Auth's codes for a uid, email address or phone number too malformed
// to look up. checkOptions catches most of these before anything is printed;
// Auth itself still rejects, for example, a number too short to be real.
const MALFORMED_SELECTOR_CODES = [
  "auth/invalid-uid",
  "auth/invalid-email",
  "auth/invalid-phone-number",
];

function usage() {
  console.log(
    [
      "Usage: node scripts/delete-account.js (--uid <uid> | --email <address> | --phone <+number>)",
      "         --expect-name <code> [--apply --project <id>]",
      "",
      "  --uid <uid>            The account's uid: its users/{uid} document id.",
      "  --email <address>      Find the account by the email address it signs in with.",
      "  --phone <+number>      Find the account by the phone number it signs in with,",
      "                         in international format, like +15551234567.",
      "  --expect-name <code>   Required. Refuses unless the profile's display name is",
      "                         exactly this.",
      "  --project <id>         Firebase project to target. --apply requires it; a dry",
      "                         run without it uses GOOGLE_CLOUD_PROJECT /",
      "                         GCLOUD_PROJECT, or the Application Default",
      "                         Credentials' project.",
      "  --apply                Actually delete. Without it the script is a dry run.",
      "  --help                 Show this message.",
      "",
      "Honours FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST (set both or",
      "neither), so it can be rehearsed on the emulators.",
      "",
      "Exit status: 0 deleted, or a dry run with nothing to refuse; 1 refused;",
      "2 usage error; 3 failed (safe to run again).",
    ].join("\n")
  );
}

/** Ends the run: `message` goes to stderr, and the exit status is `exitCode`. */
class Stop extends Error {
  constructor(exitCode, message) {
    super(message);
    this.exitCode = exitCode;
  }
}

function usageError(message) {
  return new Stop(EXIT_USAGE, `error: ${message}\nRun with --help for usage.`);
}

function refusal(message) {
  return new Stop(EXIT_REFUSED, `refused: ${message}`);
}

function parseArgs(argv) {
  const opts = {
    apply: false,
    help: false,
    uid: null,
    email: null,
    phone: null,
    expectName: null,
    projectId: null,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--apply") {
      opts.apply = true;
      continue;
    }
    if (arg === "--help" || arg === "-h") {
      opts.help = true;
      continue;
    }
    const eq = arg.indexOf("=");
    const name = eq === -1 ? arg : arg.slice(0, eq);
    const field = VALUE_OPTIONS.get(name);
    if (!field) throw usageError(`Unknown argument: ${arg}`);
    let value = eq === -1 ? argv[++i] : arg.slice(eq + 1);
    // So `--expect-name --apply` can't take --apply for the code.
    if (eq === -1 && value?.startsWith("--")) value = undefined;
    if (!value) throw usageError(`${name} requires a value.`);
    if (opts[field] !== null) throw usageError(`${name} was given twice.`);
    opts[field] = value;
  }
  return opts;
}

function checkOptions(opts) {
  const selectors = ["uid", "email", "phone"].filter((field) => opts[field] !== null);
  if (selectors.length !== 1) {
    throw usageError("Pass exactly one of --uid, --email or --phone.");
  }
  if (opts.expectName === null) {
    throw usageError(
      "--expect-name <code> is required: the display name the requester set to show the account is theirs."
    );
  }
  if (opts.uid !== null && opts.uid.includes("/")) {
    throw usageError('--uid can\'t contain "/".');
  }
  // Admin Auth's own shape checks for a uid and an email address, made here
  // so a typo stops before anything is printed.
  if (opts.uid !== null && opts.uid.length > 128) {
    throw usageError("--uid takes a uid, which is at most 128 characters long.");
  }
  if (opts.email !== null && !/^[^@]+@[^@]+$/.test(opts.email)) {
    throw usageError("--email takes an email address, like name@example.com.");
  }
  if (opts.phone !== null && !/^\+\d+$/.test(opts.phone)) {
    throw usageError("--phone takes an international number: + then digits only, like +15551234567.");
  }
}

/**
 * Why the emulator variables can't be used as they are set, or null. This
 * script writes to Firestore and to Auth, so they must agree.
 */
function emulatorMismatch(env) {
  const firestore = Boolean(env.FIRESTORE_EMULATOR_HOST);
  const auth = Boolean(env.FIREBASE_AUTH_EMULATOR_HOST);
  if (firestore === auth) return null;
  const [set, unset] = firestore
    ? ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST"]
    : ["FIREBASE_AUTH_EMULATOR_HOST", "FIRESTORE_EMULATOR_HOST"];
  return (
    `${set} is set but ${unset} isn't, so this run would use an emulator for one ` +
    "and the live project for the other. Set both, or neither."
  );
}

/**
 * "lantern@example.com" → "l***@example.com": everything before the last "@"
 * but its first character is hidden. With nothing before it, or no "@" at
 * all, the whole string is.
 */
function maskEmail(email) {
  const at = email.lastIndexOf("@");
  if (at <= 0) return "***";
  return `${Array.from(email)[0]}***${email.slice(at)}`;
}

/** "+15551234567" → "+*******4567": the last four digits only. */
function maskPhone(phone) {
  const digits = phone.replace(/\D/g, "");
  return `+${"*".repeat(Math.max(digits.length - 4, 0))}${digits.slice(-4)}`;
}

/** How the command line names the account, with email and phone masked. */
function describeSelector(opts) {
  if (opts.uid !== null) return `uid ${opts.uid}`;
  if (opts.email !== null) return `email ${maskEmail(opts.email)}`;
  return `phone ${maskPhone(opts.phone)}`;
}

/**
 * The account `opts` names, as { uid, user, profile, leftovers }: its Auth
 * user record, its users/{uid} snapshot, and, when users/{uid} doesn't exist,
 * the paths of any documents still under it. A deletion that stopped in step
 * 5 can leave those, private/data among them. Null when none of the three
 * exists. --email and --phone find the uid through Auth.
 */
async function findAccount(opts, auth, db, findProfileDocs) {
  let user = null;
  try {
    if (opts.uid !== null) user = await auth.getUser(opts.uid);
    else if (opts.email !== null) user = await auth.getUserByEmail(opts.email);
    else user = await auth.getUserByPhoneNumber(opts.phone);
  } catch (error) {
    if (MALFORMED_SELECTOR_CODES.includes(error?.code)) throw usageError(error.message);
    if (error?.code !== "auth/user-not-found") throw error;
  }
  const uid = user ? user.uid : opts.uid;
  if (uid === null) return null;
  const snap = await db.doc(`users/${uid}`).get();
  const profile = snap.exists ? snap : null;
  const leftovers = profile ? [] : (await findProfileDocs(uid)).map((ref) => ref.path);
  if (!user && !profile && leftovers.length === 0) return null;
  return { uid, user, profile, leftovers };
}

function row(label, value) {
  return `  ${label.padEnd(32)}${value}`;
}

/** Up to MAX_LISTED of `items`, and how many more there are. */
function listed(items) {
  const more = items.length > MAX_LISTED ? `, … ${items.length - MAX_LISTED} more` : "";
  return `${items.slice(0, MAX_LISTED).join(", ")}${more}`;
}

/** "0", or the count and up to MAX_LISTED of `items`. */
function counted(items) {
  if (items.length === 0) return "0";
  return `${items.length}  ${listed(items)}`;
}

/** games/{gameId} for a seat's path, games/{gameId}/players/{playerId}. */
function gameOf(seatPath) {
  return seatPath.split("/").slice(0, 2).join("/");
}

/**
 * The profile's display name as the report shows it, quoted so stray spaces
 * show. Old iOS and Android builds named a new email account after its
 * address, and some of those names are still in place (docs/KNOWN-ISSUES.md),
 * including ones reset-email-display-names.js leaves alone because they
 * aren't a whole address. So a name with "@" in it is masked the way an
 * email address is. A code never has one.
 */
function displayName(profile) {
  const name = profile.get("display_name");
  if (typeof name !== "string") return "not set";
  if (name.includes("@")) return `${JSON.stringify(maskEmail(name))} (masked: it contains "@")`;
  return JSON.stringify(name);
}

function accountLines({ uid, user, profile, leftovers }, opts) {
  const providers = user ? user.providerData.map((info) => info.providerId).sort() : [];
  return [
    "account:",
    row("uid:", opts.uid !== null ? uid : `${uid} (found by ${describeSelector(opts)})`),
    ...(profile
      ? [row("display name:", displayName(profile))]
      : [
          row("display name:", `none: users/${uid} doesn't exist`),
          row("documents left under it:", counted(leftovers)),
        ]),
    row(
      "sign-in providers:",
      !user ? "none: no sign-in account" : providers.length > 0 ? providers.join(", ") : "none (guest)"
    ),
    row("email:", user?.email ? maskEmail(user.email) : "none"),
    row("phone:", user?.phoneNumber ? maskPhone(user.phoneNumber) : "none"),
  ];
}

/**
 * Refuses unless the profile's display name is exactly `expectName`. A uid
 * with neither a sign-in account nor a profile, only documents left under
 * users/{uid}, has no name to check and no owner left to protect, so it
 * passes: a mistyped uid can reach only what a deleted account left behind.
 */
function checkName({ uid, user, profile, leftovers }, expectName) {
  if (!user && !profile) return;
  if (!profile) {
    const left = leftovers.length > 0 ? ` Documents are still left under it: ${listed(leftovers)}.` : "";
    throw refusal(
      `users/${uid} doesn't exist, so there's no display name to check --expect-name against.${left} ` +
        `If an earlier --apply for this account stopped part-way, delete the sign-in account ${uid} ` +
        `in the Firebase console (Authentication), then run this again with --uid ${uid}: with no ` +
        `sign-in account or profile left, it deletes anything still under users/${uid} without ` +
        "checking the name. If not, the account has no profile yet: its owner makes one by signing " +
        "in to Treachery on the web or Android, and can then set the code."
    );
  }
  if (profile.get("display_name") !== expectName) {
    throw refusal(
      `the display name is ${displayName(profile)}, not ${JSON.stringify(expectName)}. ` +
        "It must match --expect-name exactly."
    );
  }
}

function planLines({ uid, user }, plan) {
  const lobbies = plan.lobbies.map(({ gameId, hosted }) => `games/${gameId}${hosted ? " (hosts it)" : ""}`);
  return [
    "deleting it would:",
    row("leave waiting lobbies:", counted(lobbies)),
    row("anonymize its seats in games:", counted(plan.seatPaths.map(gameOf))),
    row("take it off friends' lists:", counted(plan.friendPaths)),
    row("delete friend requests:", counted(plan.requestPaths)),
    row("delete profile documents:", counted(plan.profilePaths)),
    row("delete the sign-in account:", counted(user ? [uid] : [])),
  ];
}

/**
 * What the deletion did. When this run deleted the sign-in account, it adds
 * when to check that the account stayed deleted: a web or Android app still
 * signed in to it holds an ID token that stays valid for up to an hour, and
 * the apps write a profile for a signed-in account that has none. --email
 * and --phone can't find such a profile, because they look the account up
 * in Auth, so the check is by uid.
 */
function summaryLines(uid, deleted) {
  const lines = [
    `deleted ${uid}:`,
    row("left waiting lobbies:", counted(deleted.lobbyIds.map((gameId) => `games/${gameId}`))),
    row("anonymized its seats in games:", counted(deleted.seatPaths.map(gameOf))),
    row("took it off friends' lists:", String(deleted.friends)),
    row("deleted friend requests:", String(deleted.requests)),
    row("deleted the profile:", `users/${uid} and everything under it`),
    row("deleted the sign-in account:", deleted.signInDeleted ? "yes" : "no, it was already deleted"),
  ];
  if (!deleted.signInDeleted) return lines;
  return [
    ...lines,
    "",
    "A web or Android app still signed in to it can recreate its profile until an hour from now.",
    `Then run this with --uid ${uid} and without --apply: it should find no such account.`,
  ];
}

function print(lines) {
  for (const line of lines) console.log(line);
}

/** Runs the script on `argv` and resolves to its exit status; throws a Stop to end it early. */
async function main(argv, env) {
  const opts = parseArgs(argv);
  if (opts.help) {
    usage();
    return EXIT_DONE;
  }
  checkOptions(opts);
  const mismatch = emulatorMismatch(env);
  if (mismatch) throw usageError(mismatch);
  const target = await resolveTarget(opts, env);
  if (target.error) throw usageError(target.error);
  print(describeTarget(target, opts.apply));
  const authHost = env.FIREBASE_AUTH_EMULATOR_HOST;
  console.log(`auth:     ${authHost ? `emulator ${authHost}` : "LIVE Firebase Auth"}`);
  console.log("");

  // The id is always explicit, so Firestore and Auth use the project printed
  // above. The deletion code is loaded only now, because src/firebase.js
  // makes its own app from the environment unless this one already exists.
  initializeApp({ projectId: target.projectId });
  const { db, getAuth } = require("../src/firebase");
  const { deleteAccountFor, planAccountDeletion, findProfileDocs } = require("../src/callables/account");

  const account = await findAccount(opts, getAuth(), db, findProfileDocs);
  if (!account) {
    throw refusal(
      opts.uid !== null
        ? `no such account: no sign-in account or profile has uid ${opts.uid}, and nothing is left under users/${opts.uid}.`
        : `no such account: no sign-in account has ${describeSelector(opts)}.`
    );
  }
  print(accountLines(account, opts));
  console.log("");
  checkName(account, opts.expectName);
  if (!account.user && !account.profile) {
    console.log("No sign-in account or profile is left, only what an earlier deletion left behind, so --expect-name isn't checked.");
    console.log("");
  }

  const plan = await planAccountDeletion(account.uid);
  if (plan.inProgressGameIds.length > 0) {
    const games = plan.inProgressGameIds.map((gameId) => `games/${gameId}`).join(", ");
    throw refusal(
      `${account.uid} is in, or hosts, a game in progress: ${games}. It can be deleted once ` +
        "that game ends; a game with no activity for 24 hours is removed automatically."
    );
  }
  print(planLines(account, plan));
  console.log("");

  if (!opts.apply) {
    console.log("DRY RUN — nothing was written. Re-run with --apply --project <id> to delete this account.");
    return EXIT_DONE;
  }

  console.log(`deleting ${account.uid} from ${target.projectId} …`);
  let deleted;
  try {
    deleted = await deleteAccountFor(account.uid);
  } catch (error) {
    if (error instanceof HttpsError && error.code === "failed-precondition") {
      throw refusal(
        `${account.uid} is now in a game in progress: a lobby it was in started after the check. ` +
          "The deletion stopped before changing anything but the lobbies it had already left. " +
          "Run this again once that game ends."
      );
    }
    console.error(error);
    throw new Stop(
      EXIT_FAILED,
      "failed: the deletion stopped part-way. Every step is safe to repeat, so run the same " +
        `command again to finish. If that is refused because users/${account.uid} doesn't exist, ` +
        `this run got as far as deleting the profile: delete the sign-in account ${account.uid} ` +
        `in the Firebase console (Authentication), then run this again with --uid ${account.uid} ` +
        `to delete anything still under users/${account.uid}.`
    );
  }
  print(summaryLines(account.uid, deleted));
  return EXIT_DONE;
}

if (require.main === module) {
  main(process.argv.slice(2), process.env).then(
    (exitCode) => {
      process.exitCode = exitCode;
    },
    (error) => {
      if (error instanceof Stop) {
        console.error(error.message);
        process.exitCode = error.exitCode;
        return;
      }
      // Every write is inside main's try around deleteAccountFor, so an error
      // that reaches here came before the first one.
      console.error(error);
      console.error(
        "failed: nothing was written. Fix what the error above names (often credentials, " +
          "permissions or the network), then run the same command again."
      );
      process.exitCode = EXIT_FAILED;
    }
  );
}
