#!/usr/bin/env node
/**
 * reset-email-display-names.js — take email addresses out of public names.
 *
 * Until the clients were fixed, iOS and Android set a new email account's
 * public display_name to its full email address, and a user who skipped the
 * name prompt kept it. Every signed-in user can read users/{uid}, friend
 * search matches on display_name, lobbies copy the name onto the player's
 * seat, and a friend request copies the sender's name for its recipient, so
 * those addresses are visible to other players. backfill-user-pii.js moves
 * email / phone_number / fcm_token but never touches display_name, so it
 * does not catch these.
 *
 * This script resets every name containing "@" to the name the clients'
 * name prompt suggests for that address: the part before the first "@",
 * trimmed, with its first letter capitalized; "Player" if that part is
 * empty. It covers:
 *
 *   users/{uid}.display_name                          public profiles
 *   games/{gameId}/players/{playerId}.display_name    seats, in every game state
 *   friend_requests/{id}.from_display_name            the sender's name, which
 *                                                     neither side can delete
 *
 * It prints document paths and counts but never a name: the old and the new
 * name both come from an email address.
 *
 * DRY RUN BY DEFAULT — it reads and reports, and writes nothing at all until
 * you pass --apply.
 *
 *   Dry run (default):
 *     cd functions && node scripts/reset-email-display-names.js --project <project-id>
 *
 *   Apply:
 *     cd functions && node scripts/reset-email-display-names.js --project <project-id> --apply
 *
 *   Rehearse against the emulator (no real data touched):
 *     FIRESTORE_EMULATOR_HOST=localhost:8087 \
 *       node scripts/reset-email-display-names.js --project demo-treachery --apply
 *
 * Run it once the fixed clients are out: app versions from before the fix
 * still name new email accounts after their address until they update. It is
 * safe to re-run then and later. A reset name never contains "@", so a pass
 * over clean data writes nothing.
 *
 * Every write updates the one name field, and only if the document is
 * unchanged since this run read it. So it never recreates a document deleted
 * meanwhile, and never overwrites a name changed meanwhile: a rename, or the
 * "Deleted player" deleteAccount puts on a seat. Such documents are counted
 * as skipped; re-running picks up any that still need it.
 *
 * Credentials come from the usual Application Default Credentials
 * (GOOGLE_APPLICATION_CREDENTIALS or `gcloud auth application-default login`);
 * when FIRESTORE_EMULATOR_HOST is set they are not needed.
 */

const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldPath } = require("firebase-admin/firestore");

// What a name with nothing before its "@" becomes (the prompt's default too).
const FALLBACK_NAME = "Player";

const PAGE_SIZE = 200; // docs read per page
const MAX_PLAN_LINES = 20; // per-doc detail lines before we go quiet

// The gRPC statuses of an update refused because its document was deleted,
// or changed, after this run read it.
const FIRESTORE_NOT_FOUND = 5;
const FIRESTORE_FAILED_PRECONDITION = 9;

function usage() {
  console.log(
    [
      "Usage: node scripts/reset-email-display-names.js [--project <id>] [--apply]",
      "",
      "  --project <id>   Firestore project to target (defaults to",
      "                   GOOGLE_CLOUD_PROJECT / GCLOUD_PROJECT).",
      "  --apply          Actually write. Without it the script is a dry run.",
      "  --help           Show this message.",
      "",
      "Honours FIRESTORE_EMULATOR_HOST, so it can be rehearsed on the emulator.",
    ].join("\n")
  );
}

function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

function parseArgs(argv) {
  const opts = { apply: false, projectId: null };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--apply") {
      opts.apply = true;
    } else if (arg === "--project") {
      opts.projectId = argv[++i] || null;
      if (!opts.projectId) fail("--project requires a project id.");
    } else if (arg.startsWith("--project=")) {
      opts.projectId = arg.slice("--project=".length) || null;
      if (!opts.projectId) fail("--project requires a project id.");
    } else if (arg === "--help" || arg === "-h") {
      usage();
      process.exit(0);
    } else {
      fail(`Unknown argument: ${arg}`);
    }
  }
  return opts;
}

/**
 * The name that replaces `name`, or null when `name` holds no "@". Matches
 * the name prompt's suggestion on iOS and Android: the part before the first
 * "@" with its first letter capitalized.
 */
function resetName(name) {
  if (typeof name !== "string" || !name.includes("@")) return null;
  const localPart = name.slice(0, name.indexOf("@")).trim();
  if (localPart === "") return FALLBACK_NAME;
  const [first, ...rest] = Array.from(localPart);
  return first.toUpperCase() + rest.join("");
}

/**
 * Counts the name updates and, with `apply`, sends each through a
 * BulkWriter as an update that requires its document to be unchanged since
 * it was read (`doc.updateTime`). A refused update is counted as skipped,
 * any other failure as failed; neither stops the run.
 */
function createWriter(db, apply) {
  const bulkWriter = apply ? db.bulkWriter() : null;
  const totals = { planned: 0, updated: 0, skipped: 0, failed: 0 };
  const results = [];

  return {
    totals,
    update(doc, data) {
      totals.planned++;
      if (!bulkWriter) return;
      results.push(
        bulkWriter.update(doc.ref, data, { lastUpdateTime: doc.updateTime }).then(
          () => {
            totals.updated++;
          },
          (error) => {
            if (
              error.code === FIRESTORE_FAILED_PRECONDITION ||
              error.code === FIRESTORE_NOT_FOUND
            ) {
              totals.skipped++;
            } else {
              totals.failed++;
              // Path and status only: a message could quote the name.
              console.error(`  ${doc.ref.path}: update failed (gRPC status ${error.code})`);
            }
          }
        )
      );
    },
    /** Waits for every queued update to be written, skipped or failed. */
    async close() {
      if (!bulkWriter) return;
      await bulkWriter.close();
      await Promise.all(results);
    },
  };
}

/**
 * Pages through `query` by document id, handing each page's docs to
 * `onPage`. Only `field` is fetched.
 */
async function forEachPage(query, field, onPage) {
  let lastDoc = null;
  let scanned = 0;
  for (;;) {
    let page = query.orderBy(FieldPath.documentId()).select(field).limit(PAGE_SIZE);
    if (lastDoc) page = page.startAfter(lastDoc);
    // Deliberate sequential await (no-await-in-loop): pages are cursors.
    const snap = await page.get();
    if (snap.empty) break;
    scanned += snap.size;
    lastDoc = snap.docs[snap.docs.length - 1];
    await onPage(snap.docs);
    if (snap.size < PAGE_SIZE) break;
  }
  return scanned;
}

/** True for games/{gameId}/players/{playerId}, the only seat docs. */
function isSeat(ref) {
  const game = ref.parent.parent;
  return game !== null && game.parent.id === "games" && game.parent.parent === null;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const projectId =
    opts.projectId ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.GCLOUD_PROJECT ||
    null;
  const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST || null;

  // The emulator infers nothing from credentials, so it needs an explicit id.
  if (emulatorHost && !projectId) {
    fail("FIRESTORE_EMULATOR_HOST is set but no project id — pass --project <id>.");
  }

  initializeApp(projectId ? { projectId } : undefined);
  const db = getFirestore();

  console.log(`project:  ${projectId || "(from application default credentials)"}`);
  console.log(`target:   ${emulatorHost ? `emulator ${emulatorHost}` : "LIVE Firestore"}`);
  console.log(`mode:     ${opts.apply ? "APPLY (writes)" : "DRY RUN (no writes)"}`);
  console.log("");

  const stats = {
    users: { scanned: 0, reset: 0, fallback: 0 },
    seats: { scanned: 0, reset: 0, fallback: 0, byState: {} },
    requests: { scanned: 0, reset: 0, fallback: 0 },
  };
  const writer = createWriter(db, opts.apply);
  let planLines = 0;
  function plan(line) {
    if (planLines < MAX_PLAN_LINES) {
      console.log(`  ${line}`);
    } else if (planLines === MAX_PLAN_LINES) {
      console.log("  … further per-doc detail suppressed");
    }
    planLines++;
  }

  // 1. Public profiles.
  stats.users.scanned = await forEachPage(db.collection("users"), "display_name", async (docs) => {
    for (const doc of docs) {
      const name = resetName(doc.get("display_name"));
      if (name === null) continue;
      stats.users.reset++;
      if (name === FALLBACK_NAME) stats.users.fallback++;
      plan(`users/${doc.id}: reset display_name`);
      writer.update(doc, { display_name: name });
    }
  });

  // 2. Seats, in every game state. A collection-group query also reaches
  //    seats whose game doc is gone; they are reported as "no game doc".
  stats.seats.scanned = await forEachPage(db.collectionGroup("players"), "display_name", async (docs) => {
    const resets = docs
      .filter((doc) => isSeat(doc.ref))
      .map((doc) => ({ doc, name: resetName(doc.get("display_name")) }))
      .filter(({ name }) => name !== null);
    if (resets.length === 0) return;

    // Each game once: getAll resolves its responses by path.
    const gameRefs = new Map();
    for (const { doc } of resets) gameRefs.set(doc.ref.parent.parent.path, doc.ref.parent.parent);
    const gameSnaps = await db.getAll(...gameRefs.values(), { fieldMask: ["state"] });
    const stateByPath = new Map(
      gameSnaps.map((snap) => [snap.ref.path, snap.exists ? snap.get("state") || "unknown" : "no game doc"])
    );

    for (const { doc, name } of resets) {
      const state = stateByPath.get(doc.ref.parent.parent.path);
      stats.seats.reset++;
      if (name === FALLBACK_NAME) stats.seats.fallback++;
      stats.seats.byState[state] = (stats.seats.byState[state] || 0) + 1;
      plan(`${doc.ref.path} (${state}): reset display_name`);
      writer.update(doc, { display_name: name });
    }
  });

  // 3. Friend requests: the sender's name as the recipient sees it.
  stats.requests.scanned = await forEachPage(
    db.collection("friend_requests"),
    "from_display_name",
    async (docs) => {
      for (const doc of docs) {
        const name = resetName(doc.get("from_display_name"));
        if (name === null) continue;
        stats.requests.reset++;
        if (name === FALLBACK_NAME) stats.requests.fallback++;
        plan(`friend_requests/${doc.id}: reset from_display_name`);
        writer.update(doc, { from_display_name: name });
      }
    }
  );

  await writer.close();

  const byState = Object.entries(stats.seats.byState)
    .map(([state, count]) => `${state} ${count}`)
    .join(", ");
  const totals = writer.totals;
  console.log("");
  console.log("─".repeat(56));
  console.log(`user docs scanned:              ${stats.users.scanned}`);
  console.log(
    `  display names with "@":       ${stats.users.reset} (${stats.users.fallback} become "${FALLBACK_NAME}")`
  );
  console.log(`seat docs scanned:              ${stats.seats.scanned}`);
  console.log(
    `  display names with "@":       ${stats.seats.reset} (${stats.seats.fallback} become "${FALLBACK_NAME}")`
  );
  if (byState) console.log(`  by game state:                ${byState}`);
  console.log(`friend requests scanned:        ${stats.requests.scanned}`);
  console.log(
    `  sender names with "@":        ${stats.requests.reset} (${stats.requests.fallback} become "${FALLBACK_NAME}")`
  );
  if (opts.apply) {
    console.log(
      `writes:                         ${totals.updated} updated, ${totals.skipped} skipped, ` +
        `${totals.failed} failed (of ${totals.planned})`
    );
  } else {
    console.log(`writes:                         ${totals.planned} planned`);
  }
  console.log("─".repeat(56));
  if (!opts.apply) {
    console.log("DRY RUN — nothing was written. Re-run with --apply to reset these names.");
    return;
  }
  if (totals.skipped > 0) {
    console.log("Skipped documents changed or were deleted after this run read them. Re-run to pick up any that still need it.");
  }
  if (totals.failed > 0) {
    console.log("Some updates failed. Re-run to retry them.");
    process.exitCode = 1;
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

// For the emulator rehearsal harness.
module.exports = { resetName, createWriter };
