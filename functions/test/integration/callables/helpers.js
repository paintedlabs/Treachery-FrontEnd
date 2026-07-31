'use strict';

/**
 * Shared harness for the Cloud Functions INTEGRATION suite.
 *
 * Unlike test/game-logic.test.js (which re-implements the logic it checks),
 * everything here drives the REAL callables exported from functions/index.js
 * as they run inside the Firebase emulator.
 *
 * Strategy: the Firebase **client** SDK (firebase/app + firebase/auth +
 * firebase/functions) pointed at the emulators. Every test user is a real
 * anonymous Auth account, so `request.auth.uid` inside the callable is
 * populated exactly the way it is in production and every auth/permission
 * branch is genuinely exercised. `firebase-admin` (which bypasses security
 * rules) is used only to seed fixtures and to read back resulting state.
 *
 * Ports are owned by this suite alone — see firebase.emulators.json.
 */

const assert = require('node:assert/strict');
const crypto = require('node:crypto');

const { initializeApp: initAdminApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const { initializeApp: initClientApp, deleteApp } = require('firebase/app');
const {
  getAuth,
  connectAuthEmulator,
  signInAnonymously,
} = require('firebase/auth');
const {
  getFunctions,
  connectFunctionsEmulator,
  httpsCallable,
} = require('firebase/functions');

// ── Emulator wiring ─────────────────────────────────────────────
// `firebase emulators:exec` exports FIRESTORE_EMULATOR_HOST and
// FIREBASE_AUTH_EMULATOR_HOST; the functions port has no standard env var,
// so it is read from INTEGRATION_FUNCTIONS_PORT with a matching default.

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'demo-test';
const AUTH_EMULATOR_URL = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9299'}`;
const FUNCTIONS_PORT = Number(process.env.INTEGRATION_FUNCTIONS_PORT || 5201);
const FUNCTIONS_HOST = process.env.INTEGRATION_FUNCTIONS_HOST || '127.0.0.1';

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8288';
}

initAdminApp({ projectId: PROJECT_ID });
const db = getFirestore();

// ── Card data (read-only reference used for expectations) ───────

const CARDS = require('../../../identityCards.json');
const cardById = (id) => CARDS.find((c) => c.id === id);
const cardsForRole = (role) => CARDS.filter((c) => c.role === role);

/**
 * The documented role distribution. This is the SPEC the suite asserts
 * against — deliberately a literal table, not a call into index.js.
 */
const EXPECTED_DISTRIBUTION = {
  4: { leader: 1, guardian: 0, assassin: 2, traitor: 1 },
  5: { leader: 1, guardian: 1, assassin: 2, traitor: 1 },
  6: { leader: 1, guardian: 1, assassin: 3, traitor: 1 },
  7: { leader: 1, guardian: 2, assassin: 3, traitor: 1 },
  8: { leader: 1, guardian: 2, assassin: 3, traitor: 2 },
};

/** The four traitors whose rarity is `uncommon`. */
const UNCOMMON_TRAITORS = ['traitor_01', 'traitor_04', 'traitor_05', 'traitor_08'];

// ── Client-SDK test users ───────────────────────────────────────

let appCounter = 0;
const clientApps = [];
const userPool = [];

function newClientApp() {
  const name = `it-client-${process.pid}-${appCounter++}`;
  const app = initClientApp(
    { projectId: PROJECT_ID, apiKey: 'demo-key', appId: 'demo-app' },
    name
  );
  const auth = getAuth(app);
  connectAuthEmulator(auth, AUTH_EMULATOR_URL, { disableWarnings: true });
  const fns = getFunctions(app);
  connectFunctionsEmulator(fns, FUNCTIONS_HOST, FUNCTIONS_PORT);
  clientApps.push(app);
  return { app, auth, fns };
}

function makeCaller(fns) {
  return async (name, data) => {
    const res = await httpsCallable(fns, name)(data);
    return res.data;
  };
}

/**
 * A signed-in test user. `call(name, data)` invokes a callable with this
 * user's ID token attached, which is what populates request.auth.uid.
 */
async function createUser(label) {
  const { app, auth, fns } = newClientApp();
  const cred = await signInAnonymously(auth);
  const uid = cred.user.uid;
  const displayName = label || `Player ${userPool.length + 1}`;
  await db.doc(`users/${uid}`).set({
    display_name: displayName,
    elo: 1500,
    created_at: FieldValue.serverTimestamp(),
  });
  return { uid, displayName, app, auth, call: makeCaller(fns) };
}

/** Returns (creating on first use) `n` reusable signed-in test users. */
async function getUsers(n) {
  while (userPool.length < n) {
    // eslint-disable-next-line no-await-in-loop
    userPool.push(await createUser(`Player ${userPool.length + 1}`));
  }
  return userPool.slice(0, n);
}

let anonCaller = null;
/** A caller with NO signed-in user — exercises the `unauthenticated` branch. */
function unauthenticatedCaller() {
  if (!anonCaller) {
    const { fns } = newClientApp();
    anonCaller = makeCaller(fns);
  }
  return anonCaller;
}

// ── Fixtures ────────────────────────────────────────────────────

/** Wide enough that parallel test files never collide on a lobby code. */
function uniqueCode() {
  return crypto.randomBytes(6).toString('hex').toUpperCase();
}

/**
 * Seeds a lobby straight into Firestore with firebase-admin (bypasses rules,
 * which is what the app's own Cloud Functions do anyway).
 *
 * Player doc ids are deterministic: p0, p1, ... in seat order.
 */
async function seedGame({
  users,
  host,
  state = 'waiting',
  gameMode = 'treachery',
  startingLife = 40,
  maxPlayers = 8,
  maxTraitorRarity,
  planechase,
  playerOverrides = {},
  gameFields = {},
} = {}) {
  assert.ok(users && users.length > 0, 'seedGame requires at least one user');
  const hostUser = host || users[0];
  const code = uniqueCode();
  const gameRef = db.collection('games').doc();

  const gameDoc = {
    code,
    host_id: hostUser.uid,
    player_ids: users.map((u) => u.uid),
    state,
    game_mode: gameMode,
    starting_life: startingLife,
    max_players: maxPlayers,
    created_at: FieldValue.serverTimestamp(),
    last_activity_at: FieldValue.serverTimestamp(),
    ...gameFields,
  };
  if (maxTraitorRarity !== undefined) gameDoc.max_traitor_rarity = maxTraitorRarity;
  if (planechase !== undefined) gameDoc.planechase = planechase;

  await gameRef.set(gameDoc);

  const players = [];
  const batch = db.batch();
  users.forEach((u, i) => {
    const id = `p${i}`;
    const ref = gameRef.collection('players').doc(id);
    batch.set(ref, {
      user_id: u.uid,
      display_name: u.displayName,
      order_id: i,
      role: null,
      identity_card_id: null,
      life_total: startingLife,
      is_eliminated: false,
      is_unveiled: false,
      joined_at: FieldValue.serverTimestamp(),
      ...(playerOverrides[i] || {}),
    });
    players.push({ id, uid: u.uid, user: u, seat: i });
  });
  await batch.commit();

  return { gameId: gameRef.id, code, ref: gameRef, host: hostUser, users, players };
}

/**
 * Seeds a lobby and then starts it for real via the `startGame` callable,
 * using the emulator-only testSeed hook for deterministic role/card layout.
 *
 * `seats` is aligned with `users`: [{ role, card }, ...]
 */
async function seedStartedGame({ users, seats, ...rest }) {
  const game = await seedGame({ users, ...rest });
  const assignments = {};
  users.forEach((u, i) => {
    assignments[u.uid] = { role: seats[i].role, identityCardId: seats[i].card };
  });
  await game.host.call('startGame', { gameId: game.gameId, testSeed: { assignments } });
  return game;
}

// ── Reads / mutations for assertions & mid-test state setup ─────

async function getGame(gameId) {
  const snap = await db.doc(`games/${gameId}`).get();
  return snap.exists ? { id: snap.id, ...snap.data() } : null;
}

async function getPlayers(gameId) {
  const snap = await db.collection(`games/${gameId}/players`).orderBy('order_id').get();
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

async function getPlayer(gameId, playerDocId) {
  const snap = await db.doc(`games/${gameId}/players/${playerDocId}`).get();
  return snap.exists ? { id: snap.id, ...snap.data() } : null;
}

/** Directly edits a player doc to set up a mid-game state. */
function patchPlayer(gameId, playerDocId, patch) {
  return db.doc(`games/${gameId}/players/${playerDocId}`).update(patch);
}

/** Directly edits the game doc to set up a mid-game state. */
function patchGame(gameId, patch) {
  return db.doc(`games/${gameId}`).update(patch);
}

// ── Assertions ──────────────────────────────────────────────────

/**
 * Awaits `promise`, asserting it rejects with the given HttpsError code.
 * The client SDK prefixes codes with "functions/", which is normalised away.
 */
async function expectHttpsError(promise, expectedCode) {
  let error = null;
  let resolved;
  let didResolve = false;
  try {
    resolved = await promise;
    didResolve = true;
  } catch (e) {
    error = e;
  }
  if (didResolve) {
    assert.fail(
      `Expected HttpsError "${expectedCode}" but the call succeeded with ${JSON.stringify(resolved)}`
    );
  }
  const code = String(error.code || '').replace(/^functions\//, '');
  assert.equal(
    code,
    expectedCode,
    `Expected HttpsError "${expectedCode}" but got "${code}": ${error.message}`
  );
  return error;
}

/** Counts roles across player docs. */
function roleCounts(players) {
  const counts = { leader: 0, guardian: 0, assassin: 0, traitor: 0 };
  for (const p of players) {
    assert.ok(
      Object.prototype.hasOwnProperty.call(counts, p.role),
      `Unexpected role assigned: ${JSON.stringify(p.role)}`
    );
    counts[p.role] += 1;
  }
  return counts;
}

// ── Teardown ────────────────────────────────────────────────────

async function shutdown() {
  await Promise.all(clientApps.map((a) => deleteApp(a).catch(() => {})));
  clientApps.length = 0;
  userPool.length = 0;
  anonCaller = null;
  await db.terminate().catch(() => {});
}

module.exports = {
  db,
  FieldValue,
  CARDS,
  cardById,
  cardsForRole,
  EXPECTED_DISTRIBUTION,
  UNCOMMON_TRAITORS,
  getUsers,
  createUser,
  unauthenticatedCaller,
  seedGame,
  seedStartedGame,
  getGame,
  getPlayers,
  getPlayer,
  patchPlayer,
  patchGame,
  expectHttpsError,
  roleCounts,
  shutdown,
};
