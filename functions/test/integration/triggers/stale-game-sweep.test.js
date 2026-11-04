'use strict';

/**
 * INTEGRATION: the hourly stale-game sweep, exports.cleanupStaleGames
 * (functions/index.js, implemented in functions/src/triggers.js).
 *
 * The emulator never fires scheduled functions (without a Pub/Sub emulator
 * it logs "function ignored"), so this file runs the sweep's body,
 * sweepStaleGames, in-process against the Firestore emulator with a fixed
 * clock. It loads the production module, whose src/firebase.js owns the
 * default Admin app, and seeds through that same `db`. The callables harness
 * (../callables/helpers.js) initialises the default app with explicit
 * options, and firebase-admin refuses to initialise it a second way, so the
 * two cannot share a process.
 *
 * Not covered: the emulator does not enforce composite indexes, so a sweep
 * query that would fail in production with FAILED_PRECONDITION passes here.
 * test/game-logic.test.js checks firestore.indexes.json for that.
 */

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');

// Same wiring as the callables harness: `firebase emulators:exec` exports
// these, and the fallbacks match ../callables/firebase.emulators.json.
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8288';
}
if (!process.env.GCLOUD_PROJECT) {
  process.env.GCLOUD_PROJECT = 'demo-test';
}
const HUB_HOST = process.env.FIREBASE_EMULATOR_HUB || '127.0.0.1:4460';

// The sweep deletes games: never point this file at a real project.
assert.match(process.env.GCLOUD_PROJECT, /^demo-/, 'the sweep test only runs against a demo-* project');

const { db } = require('../../../src/firebase');
const { sweepStaleGames } = require('../../../src/triggers');

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

// A fixed clock long before any real run. Every other suite stamps its games
// with the real time, so only games seeded here can be older than this
// clock's cutoff (24 hours before it).
const NOW = new Date('2026-01-15T12:00:00Z');

/** PUT to the emulator hub, e.g. to pause or resume background triggers. */
async function hubPut(path) {
  const res = await fetch(`http://${HUB_HOST}${path}`, { method: 'PUT' });
  assert.ok(res.ok, `emulator hub ${path} answered HTTP ${res.status}`);
}

// onPlayerJoined fires for every players doc written while the functions
// emulator runs, and stamps the game's last_activity_at with the real time,
// which would make every seeded game look active. Background triggers stay
// paused for the whole file (the hub endpoints behind
// @firebase/rules-unit-testing's withFunctionTriggersDisabled), so an event
// delivered late is dropped instead of landing mid-test.
before(async () => {
  await hubPut('/functions/disableBackgroundTriggers');
});

after(async () => {
  try {
    await hubPut('/functions/enableBackgroundTriggers');
  } finally {
    await db.terminate();
  }
});

let seededGames = 0;

/**
 * Writes one game and its player docs with firebase-admin. Only state,
 * created_at and last_activity_at matter to the sweep; the other fields keep
 * the docs game-shaped. Leave lastActivityAt out for a legacy game written
 * before that field existed.
 */
async function seedGame({ state, createdAt, lastActivityAt, playerCount = 2 }) {
  const ref = db.collection('games').doc();
  const uids = Array.from({ length: playerCount }, (_, i) => `sweep-${ref.id}-${i}`);
  const game = {
    code: `SWEEP${seededGames++}`,
    host_id: uids[0],
    player_ids: uids,
    state,
    game_mode: 'treachery',
    starting_life: 40,
    max_players: 8,
    created_at: createdAt,
  };
  if (lastActivityAt) game.last_activity_at = lastActivityAt;

  const batch = db.batch();
  batch.set(ref, game);
  uids.forEach((uid, i) => {
    batch.set(ref.collection('players').doc(`p${i}`), {
      user_id: uid,
      display_name: `Player ${i + 1}`,
      order_id: i,
    });
  });
  await batch.commit();
  return ref;
}

/** A game doc and its player docs as stored, with their last write times. */
async function readGame(ref) {
  const [game, players] = await Promise.all([ref.get(), ref.collection('players').get()]);
  return {
    exists: game.exists,
    data: game.data(),
    updateTime: game.updateTime,
    players: players.docs.map((p) => ({ id: p.id, data: p.data(), updateTime: p.updateTime })),
  };
}

describe('sweepStaleGames', () => {
  it('deletes exactly the stale waiting and in-progress games, with their players', async () => {
    const ago = (ms) => new Date(NOW.getTime() - ms);
    const stale = {
      waiting: await seedGame({
        state: 'waiting',
        createdAt: ago(3 * DAY),
        lastActivityAt: ago(2 * DAY),
      }),
      inProgress: await seedGame({
        state: 'in_progress',
        createdAt: ago(3 * DAY),
        lastActivityAt: ago(25 * HOUR),
      }),
      // Written before last_activity_at existed: only created_at is set.
      legacyInProgress: await seedGame({ state: 'in_progress', createdAt: ago(3 * DAY) }),
    };
    const kept = {
      // Found by the created_at query; the recent-activity check must keep it.
      oldButActive: await seedGame({
        state: 'in_progress',
        createdAt: ago(3 * DAY),
        lastActivityAt: ago(HOUR),
      }),
      // Just inside the 24-hour window.
      recent: await seedGame({
        state: 'waiting',
        createdAt: ago(23 * HOUR),
        lastActivityAt: ago(23 * HOUR),
      }),
      // Finished games are history, however old.
      oldFinished: await seedGame({
        state: 'finished',
        createdAt: ago(30 * DAY),
        lastActivityAt: ago(30 * DAY),
      }),
    };

    const original = {};
    for (const [name, ref] of Object.entries({ ...stale, ...kept })) {
      original[name] = await readGame(ref);
      assert.equal(original[name].players.length, 2, `the ${name} game is seeded with its players`);
    }

    const result = await sweepStaleGames({ now: NOW });
    assert.deepEqual(result, { deleted: 3, failedStates: [] });

    for (const [name, ref] of Object.entries(stale)) {
      const swept = await readGame(ref);
      assert.equal(swept.exists, false, `the stale ${name} game must be deleted`);
      assert.deepEqual(swept.players, [], `the stale ${name} game's players must be deleted`);
    }
    for (const [name, ref] of Object.entries(kept)) {
      assert.deepEqual(
        await readGame(ref),
        original[name],
        `the ${name} game and its players must be untouched`
      );
    }
  });

  it('reads at most `limit` games per query, oldest first, so a backlog drains over runs', async () => {
    // A month before NOW, so every game the previous test kept is newer than
    // this cutoff and stays out of it.
    const now = new Date(NOW.getTime() - 30 * DAY);
    const ago = (ms) => new Date(now.getTime() - ms);
    const oldest = await seedGame({ state: 'waiting', createdAt: ago(5 * DAY), lastActivityAt: ago(4 * DAY) });
    const middle = await seedGame({ state: 'waiting', createdAt: ago(4 * DAY), lastActivityAt: ago(3 * DAY) });
    const newest = await seedGame({ state: 'waiting', createdAt: ago(3 * DAY), lastActivityAt: ago(2 * DAY) });

    assert.deepEqual(await sweepStaleGames({ now, limit: 2 }), { deleted: 2, failedStates: [] });
    assert.equal((await oldest.get()).exists, false, 'the oldest game goes first');
    assert.equal((await middle.get()).exists, false, 'then the next oldest');
    assert.equal((await newest.get()).exists, true, 'the third waits for the next run');

    assert.deepEqual(await sweepStaleGames({ now, limit: 2 }), { deleted: 1, failedStates: [] });
    assert.equal((await newest.get()).exists, false, 'the next run deletes it');
  });
});
