'use strict';

/**
 * INTEGRATION: exports.onGameFinished (functions/index.js), the Firestore
 * trigger that settles ELO when a game's state flips to "finished".
 *
 * A trigger runs after the write that fires it, not inside it, so these
 * tests poll for its effect against a deadline. Users come from
 * h.createUser() rather than the shared pool so every rating starts at 1500.
 */

const { describe, it, after } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

after(async () => {
  await h.shutdown();
});

/** Re-reads `read()` until `done(value)` holds; fails after `timeoutMs`. */
async function waitFor(read, done, { timeoutMs = 15000, intervalMs = 200 } = {}) {
  const deadline = Date.now() + timeoutMs;
  let value = await read();
  while (!done(value)) {
    if (Date.now() > deadline) {
      assert.fail(`Timed out after ${timeoutMs}ms; last value: ${JSON.stringify(value)}`);
    }
    // Deliberate sequential await (no-await-in-loop).
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
    value = await read();
  }
  return value;
}

async function getElo(uid) {
  const snap = await h.db.doc(`users/${uid}`).get();
  return snap.exists ? snap.data().elo : undefined;
}

describe('onGameFinished', () => {
  it("settles everyone else's ELO when one player's profile no longer exists", async () => {
    const leader = await h.createUser('Winning Leader');
    const assassin = await h.createUser('Losing Assassin');
    const deleted = await h.createUser('Deleted Traitor');
    const game = await h.seedGame({
      users: [leader, assassin, deleted],
      state: 'in_progress',
      playerOverrides: {
        0: { role: 'leader' },
        1: { role: 'assassin' },
        2: { role: 'traitor' },
      },
    });
    await h.db.doc(`users/${deleted.uid}`).delete();

    await h.patchGame(game.gameId, { state: 'finished', winning_team: 'leader' });

    // One 1500 winner against two 1500 losers: +16 for the winner, -16 for
    // each loser.
    assert.equal(await waitFor(() => getElo(leader.uid), (elo) => elo !== 1500), 1516);
    assert.equal(await waitFor(() => getElo(assassin.uid), (elo) => elo !== 1500), 1484);
    assert.equal(
      (await h.db.doc(`users/${deleted.uid}`).get()).exists,
      false,
      'the trigger must not recreate a deleted profile'
    );
  });
});
