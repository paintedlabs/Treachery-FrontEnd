'use strict';

/**
 * INTEGRATION: the onPlayerJoined Firestore trigger (functions/src/triggers.js).
 *
 * Runs the trigger's handler in-process (`.run`, which firebase-functions
 * exposes for tests) against the Firestore emulator. That covers a case the
 * emulator's own event delivery can't stage reliably: a join whose game is
 * deleted before the trigger runs. In the emulator an unhandled error there
 * kills the functions worker, so other suites' requests fail with "socket
 * hang up".
 */

const { describe, it, after } = require('node:test');
const assert = require('node:assert/strict');

// Same wiring as stale-game-sweep.test.js: `firebase emulators:exec` exports
// these, and the fallbacks match ../callables/firebase.emulators.json.
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8288';
}
if (!process.env.GCLOUD_PROJECT) {
  process.env.GCLOUD_PROJECT = 'demo-test';
}

// The handler writes games: never point this file at a real project.
assert.match(process.env.GCLOUD_PROJECT, /^demo-/, 'the trigger test only runs against a demo-* project');

const { Timestamp } = require('firebase-admin/firestore');
const { db } = require('../../../src/firebase');
const { onPlayerJoined } = require('../../../src/triggers');

after(async () => {
  await db.terminate();
});

/** The event onDocumentCreated hands the handler, reduced to what it reads. */
function joinEvent(gameId, player) {
  return { params: { gameId, playerId: 'p1' }, data: { data: () => player } };
}

describe('onPlayerJoined', () => {
  it('ends quietly when the game is already gone', async () => {
    const ref = db.collection('games').doc(); // never written

    await onPlayerJoined.run(joinEvent(ref.id, { user_id: 'joiner', display_name: 'Joiner' }));

    assert.equal((await ref.get()).exists, false, 'the trigger must not recreate the game');
  });

  it('stamps last_activity_at on a live game', async () => {
    const ref = db.collection('games').doc();
    const createdAt = Timestamp.fromDate(new Date('2026-01-15T12:00:00Z'));
    await ref.set({ state: 'waiting', host_id: 'host', player_ids: ['host'], created_at: createdAt });

    await onPlayerJoined.run(joinEvent(ref.id, { user_id: 'joiner', display_name: 'Joiner' }));

    const lastActivity = (await ref.get()).get('last_activity_at');
    assert.ok(lastActivity instanceof Timestamp, 'last_activity_at is a server timestamp');
    assert.ok(lastActivity.toMillis() > createdAt.toMillis(), 'last_activity_at is the time of the join');
  });
});
