'use strict';

/**
 * INTEGRATION: exports.createGame (functions/index.js)
 */

const { describe, it, after } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

after(async () => {
  await h.shutdown();
});

/** How many game docs `uid` hosts, read back with the Admin SDK. */
async function countGamesHostedBy(uid) {
  const snap = await h.db.collection('games').where('host_id', '==', uid).get();
  return snap.size;
}

describe('createGame — startingLife', () => {
  // Every value the create screens (iOS, web, Android) offer: 20 to 60 in
  // steps of 5. 35, 45, 55 and 60 used to be rejected.
  for (const life of [20, 25, 30, 35, 40, 45, 50, 55, 60]) {
    it(`creates the lobby at ${life} and seats the host with that life total`, async () => {
      const [host] = await h.getUsers(1);
      const { gameId } = await host.call('createGame', { startingLife: life });

      const g = await h.getGame(gameId);
      assert.equal(g.starting_life, life);

      const players = await h.getPlayers(gameId);
      assert.equal(players.length, 1);
      assert.equal(players[0].user_id, host.uid);
      assert.equal(players[0].life_total, life);
    });
  }

  it('defaults to 40 when startingLife is omitted', async () => {
    const [host] = await h.getUsers(1);
    const { gameId } = await host.call('createGame', {});
    const g = await h.getGame(gameId);
    assert.equal(g.starting_life, 40);
  });

  for (const bad of [0, 15, 41, 65, -20, 40.5, 'abc']) {
    it(`rejects the unsupported value ${JSON.stringify(bad)} without creating a game`, async () => {
      const [host] = await h.getUsers(1);
      const before = await countGamesHostedBy(host.uid);

      const err = await h.expectHttpsError(
        host.call('createGame', { startingLife: bad }),
        'invalid-argument'
      );
      // The client SDK appends the HTTP status, e.g. "... [400]".
      assert.match(err.message, /^Invalid starting life value\./);
      assert.equal(
        await countGamesHostedBy(host.uid),
        before,
        'a rejected create must not write a game'
      );
    });
  }
});
