#!/usr/bin/env node
/**
 * backfill-user-pii.js — retroactively move PII off public user documents.
 *
 * PR #108 started writing email / phone_number / fcm_token to the owner-only
 * doc `users/{uid}/private/data`, but it never touched the documents that
 * already existed. Any signed-in user can still read `users/{uid}`, so every
 * pre-existing account's email and phone number remain exposed. This script
 * closes that gap for the existing data:
 *
 *   for each users/{uid} holding email / phone_number / fcm_token:
 *     1. copy those fields into users/{uid}/private/data (merge, and never
 *        overwrite a value that is already there — the private doc wins)
 *     2. delete them from the public users/{uid} doc
 *
 * DRY RUN BY DEFAULT — it reads and reports, and writes nothing at all until
 * you pass --apply.
 *
 *   Dry run (default):
 *     cd functions && node scripts/backfill-user-pii.js --project <project-id>
 *
 *   Apply:
 *     cd functions && node scripts/backfill-user-pii.js --project <project-id> --apply
 *
 *   Rehearse against the emulator (no real data touched):
 *     FIRESTORE_EMULATOR_HOST=localhost:8288 \
 *       node scripts/backfill-user-pii.js --project demo-treachery --apply
 *
 * Safe to re-run: a second pass finds no public PII left to move and does
 * nothing. Interrupting it mid-way is safe too — each user is migrated by a
 * single batched commit, and re-running picks up whatever was not committed.
 *
 * Credentials come from the usual Application Default Credentials
 * (GOOGLE_APPLICATION_CREDENTIALS or `gcloud auth application-default login`);
 * when FIRESTORE_EMULATOR_HOST is set they are not needed.
 */

const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, FieldPath } = require("firebase-admin/firestore");

// Fields that must live only on users/{uid}/private/data
const PII_FIELDS = ["email", "phone_number", "fcm_token"];

const PAGE_SIZE = 200; // user docs read per page
const MAX_BATCH_OPS = 500; // Firestore's hard per-commit limit
const MAX_PLAN_LINES = 20; // per-user detail lines before we go quiet

function usage() {
  console.log(
    [
      "Usage: node scripts/backfill-user-pii.js [--project <id>] [--apply]",
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

// null/undefined mean "nothing to move"; anything else is a value we relocate.
function hasValue(value) {
  return value !== undefined && value !== null;
}

/**
 * Queues writes and commits them in batches that stay under the 500-op limit.
 * In dry-run mode it only counts what it would have written.
 */
function createWriter(db, apply) {
  let batch = apply ? db.batch() : null;
  let batched = 0;
  const totals = { ops: 0, commits: 0 };

  async function commit() {
    if (batched === 0) return;
    if (apply) {
      await batch.commit();
      batch = db.batch();
    }
    totals.commits++;
    batched = 0;
  }

  return {
    totals,
    /** `mutations` is applied all-or-nothing — never split across commits. */
    async add(mutations) {
      if (mutations.length === 0) return;
      if (batched + mutations.length > MAX_BATCH_OPS) await commit();
      for (const { ref, data } of mutations) {
        if (apply) batch.set(ref, data, { merge: true });
        batched++;
        totals.ops++;
      }
    },
    async flush() {
      await commit();
    },
  };
}

/**
 * Builds the mutations for one page of candidate user docs. Reads the matching
 * private docs in one getAll so an already-migrated value is never clobbered.
 */
async function planPage(db, candidates, stats) {
  const privateSnaps = await db.getAll(
    ...candidates.map((doc) => db.doc(`users/${doc.id}/private/data`))
  );

  const plans = [];
  candidates.forEach((doc, idx) => {
    const privateData = privateSnaps[idx].exists ? privateSnaps[idx].data() : {};
    const privateUpdate = {};
    const publicUpdate = {};
    const moved = [];
    const preserved = [];

    for (const field of PII_FIELDS) {
      const value = doc.get(field);
      if (!hasValue(value)) continue;
      if (hasValue(privateData[field])) {
        // Private doc already holds a value — keep it, just scrub the public copy.
        preserved.push(field);
        stats.preserved++;
        stats.fields[field].preserved++;
      } else {
        privateUpdate[field] = value;
        moved.push(field);
        stats.fields[field].moved++;
      }
      publicUpdate[field] = FieldValue.delete();
    }

    if (Object.keys(publicUpdate).length === 0) return;

    const mutations = [];
    if (Object.keys(privateUpdate).length > 0) {
      mutations.push({ ref: db.doc(`users/${doc.id}/private/data`), data: privateUpdate });
    }
    mutations.push({ ref: doc.ref, data: publicUpdate });
    plans.push({ uid: doc.id, moved, preserved, mutations });
  });

  return plans;
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

  // Per field, moved and preserved are counted apart: "moved" relocates the
  // value into private/data, "preserved" only drops the public copy because
  // private/data already held one. Collapsing them would tell an operator
  // reading the dry run that values are being relocated when they are not.
  const stats = {
    scanned: 0,
    migrated: 0,
    preserved: 0,
    fields: {
      email: { moved: 0, preserved: 0 },
      phone_number: { moved: 0, preserved: 0 },
      fcm_token: { moved: 0, preserved: 0 },
    },
  };
  const writer = createWriter(db, opts.apply);
  let planLines = 0;
  let lastDoc = null;

  for (;;) {
    let query = db.collection("users").orderBy(FieldPath.documentId()).limit(PAGE_SIZE);
    if (lastDoc) query = query.startAfter(lastDoc);
    const snap = await query.get();
    if (snap.empty) break;

    stats.scanned += snap.size;
    lastDoc = snap.docs[snap.docs.length - 1];

    const candidates = snap.docs.filter((doc) =>
      PII_FIELDS.some((field) => hasValue(doc.get(field)))
    );
    if (candidates.length > 0) {
      const plans = await planPage(db, candidates, stats);
      for (const plan of plans) {
        stats.migrated++;
        if (planLines < MAX_PLAN_LINES) {
          const details = [
            plan.moved.length > 0 ? `move ${plan.moved.join(", ")}` : null,
            plan.preserved.length > 0
              ? `drop ${plan.preserved.join(", ")} (already private)`
              : null,
          ].filter(Boolean);
          console.log(`  users/${plan.uid}: ${details.join("; ")}`);
          planLines++;
        } else if (planLines === MAX_PLAN_LINES) {
          console.log("  … further per-user detail suppressed");
          planLines++;
        }
        await writer.add(plan.mutations);
      }
    }

    if (snap.size < PAGE_SIZE) break;
  }

  await writer.flush();

  console.log("");
  console.log("─".repeat(52));
  console.log(`user docs scanned:          ${stats.scanned}`);
  console.log(`docs holding public PII:    ${stats.migrated}`);
  for (const field of PII_FIELDS) {
    const { moved, preserved } = stats.fields[field];
    console.log(
      `  ${field.padEnd(18)}  ${String(moved).padStart(6)} moved  ${String(preserved).padStart(6)} already private`
    );
  }
  console.log(`values already private:     ${stats.preserved} (kept, public copy dropped)`);
  console.log(
    `writes:                     ${writer.totals.ops} ops in ${writer.totals.commits} batch(es)`
  );
  console.log("─".repeat(52));
  if (!opts.apply) {
    console.log("DRY RUN — nothing was written. Re-run with --apply to migrate.");
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
