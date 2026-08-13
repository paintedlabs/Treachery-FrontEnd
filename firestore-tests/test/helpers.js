/**
 * Shared setup for the Firestore security-rules suite.
 *
 * Runner choice: **mocha**.
 *   `@firebase/rules-unit-testing` is entirely promise-based and needs real
 *   `before`/`after` hooks to boot and tear down a shared RulesTestEnvironment,
 *   so the monorepo's "plain node script + assert" convention (see
 *   functions/test/game-logic.test.js) doesn't fit here. Mocha was picked over
 *   vitest because it is the smaller dependency (no vite/esbuild toolchain),
 *   runs CommonJS unchanged like the rest of the repo's node code, and gives us
 *   the `it.skip` marker the vulnerability tests below rely on. Assertions come
 *   from `assertSucceeds` / `assertFails` plus node's built-in `assert`, so no
 *   extra assertion library is needed.
 */

"use strict";

const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");

// Distinct fake project so we never share emulator state with the web E2E
// suite (which uses `demo-test`).
const PROJECT_ID = "demo-rules-test";

// This suite owns port 8098. Other suites in the monorepo use 8087 / 8187 /
// 8288 / 8082, so they can all run concurrently.
const FIRESTORE_HOST = "127.0.0.1";
const FIRESTORE_PORT = 8098;

const RULES_PATH = path.resolve(__dirname, "../../firestore.rules");

let testEnv = null;

async function getTestEnv() {
  if (testEnv) return testEnv;
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      host: FIRESTORE_HOST,
      port: FIRESTORE_PORT,
      rules: fs.readFileSync(RULES_PATH, "utf8"),
    },
  });
  return testEnv;
}

async function cleanupTestEnv() {
  if (!testEnv) return;
  await testEnv.cleanup();
  testEnv = null;
}

/**
 * Seed fixture documents with rules bypassed.
 * @param {(db: import('firebase/firestore').Firestore) => Promise<void>} fn
 */
async function seed(fn) {
  const env = await getTestEnv();
  await env.withSecurityRulesDisabled(async (context) => {
    await fn(context.firestore());
  });
}

/** Firestore handle for a signed-in user. */
async function authedDb(uid, tokenOptions) {
  const env = await getTestEnv();
  return env.authenticatedContext(uid, tokenOptions).firestore();
}

/** Firestore handle for a signed-out client. */
async function anonDb() {
  const env = await getTestEnv();
  return env.unauthenticatedContext().firestore();
}

async function clearData() {
  const env = await getTestEnv();
  await env.clearFirestore();
}

// ─── Fixture factories ──────────────────────────────────────────────

/** A realistic public users/{uid} doc — PII lives under private/data. */
function userDoc(uid, overrides = {}) {
  return {
    uid,
    display_name: `Player ${uid}`,
    friend_ids: [],
    elo_rating: 1200,
    games_played: 0,
    created_at: new Date("2026-01-01T00:00:00Z"),
    ...overrides,
  };
}

/** Owner-only private bag for email / phone / FCM. */
function privateUserDoc(uid, overrides = {}) {
  return {
    email: `${uid}@example.com`,
    phone_number: "+15555550123",
    fcm_token: `fcm-token-${uid}`,
    ...overrides,
  };
}

function gameDoc(hostId, overrides = {}) {
  return {
    host_id: hostId,
    state: "waiting",
    player_ids: [hostId],
    max_players: 6,
    starting_life: 40,
    game_mode: "treachery",
    max_traitor_rarity: "mythic",
    join_code: "ABCD",
    created_at: new Date("2026-01-01T00:00:00Z"),
    last_activity_at: new Date("2026-01-01T00:00:00Z"),
    ...overrides,
  };
}

function playerDoc(userId, overrides = {}) {
  return {
    user_id: userId,
    display_name: `Player ${userId}`,
    life_total: 40,
    order_id: 0,
    is_unveiled: false,
    is_eliminated: false,
    player_color: "#4287f5",
    commander_name: "",
    role: null,
    identity_card_id: null,
    ...overrides,
  };
}

function friendRequestDoc(fromUserId, toUserId, overrides = {}) {
  return {
    from_user_id: fromUserId,
    to_user_id: toUserId,
    from_display_name: `Player ${fromUserId}`,
    status: "pending",
    created_at: new Date("2026-01-01T00:00:00Z"),
    ...overrides,
  };
}

module.exports = {
  PROJECT_ID,
  FIRESTORE_HOST,
  FIRESTORE_PORT,
  RULES_PATH,
  getTestEnv,
  cleanupTestEnv,
  seed,
  authedDb,
  anonDb,
  clearData,
  userDoc,
  privateUserDoc,
  gameDoc,
  playerDoc,
  friendRequestDoc,
  assertSucceeds,
  assertFails,
};
