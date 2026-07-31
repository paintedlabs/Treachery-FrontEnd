'use strict';

/**
 * INTEGRATION: exports.updateGameSettings (functions/index.js)
 */

const { describe, it, after } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

after(async () => {
  await h.shutdown();
});

describe('updateGameSettings — authorisation & preconditions', () => {
  it('rejects a non-host with permission-denied', async () => {
    const users = await h.getUsers(3);
    const game = await h.seedGame({ users, maxPlayers: 8 });
    await h.expectHttpsError(
      users[1].call('updateGameSettings', { gameId: game.gameId, maxPlayers: 4 }),
      'permission-denied'
    );
    const g = await h.getGame(game.gameId);
    assert.equal(g.max_players, 8, 'a rejected update must not persist');
  });

  it('rejects changes once the game is no longer waiting', async () => {
    const users = await h.getUsers(4);
    const game = await h.seedGame({ users, maxPlayers: 8 });
    await game.host.call('startGame', { gameId: game.gameId });

    await h.expectHttpsError(
      game.host.call('updateGameSettings', { gameId: game.gameId, maxPlayers: 4 }),
      'failed-precondition'
    );
    const g = await h.getGame(game.gameId);
    assert.equal(g.max_players, 8);
  });

  it('rejects an unauthenticated caller', async () => {
    const users = await h.getUsers(2);
    const game = await h.seedGame({ users });
    await h.expectHttpsError(
      h.unauthenticatedCaller()('updateGameSettings', {
        gameId: game.gameId,
        maxPlayers: 4,
      }),
      'unauthenticated'
    );
  });

  it('rejects an unknown gameId', async () => {
    const [host] = await h.getUsers(1);
    await h.expectHttpsError(
      host.call('updateGameSettings', { gameId: 'nope', maxPlayers: 4 }),
      'not-found'
    );
  });

  it('rejects a missing gameId', async () => {
    const [host] = await h.getUsers(1);
    await h.expectHttpsError(host.call('updateGameSettings', {}), 'invalid-argument');
  });
});

describe('updateGameSettings — maxPlayers', () => {
  it('persists a valid value', async () => {
    const users = await h.getUsers(2);
    const game = await h.seedGame({ users, maxPlayers: 8 });
    const res = await game.host.call('updateGameSettings', {
      gameId: game.gameId,
      maxPlayers: 6,
    });
    assert.deepEqual(res, { success: true });
    const g = await h.getGame(game.gameId);
    assert.equal(g.max_players, 6);
  });

  for (const bad of [1, 9, 0, -3]) {
    it(`rejects ${bad}`, async () => {
      const users = await h.getUsers(2);
      const game = await h.seedGame({ users, maxPlayers: 8 });
      await h.expectHttpsError(
        game.host.call('updateGameSettings', { gameId: game.gameId, maxPlayers: bad }),
        'invalid-argument'
      );
      const g = await h.getGame(game.gameId);
      assert.equal(g.max_players, 8);
    });
  }
});

describe('updateGameSettings — gameMode', () => {
  for (const mode of ['treachery', 'planechase', 'treachery_planechase', 'none']) {
    it(`persists "${mode}"`, async () => {
      const users = await h.getUsers(2);
      const game = await h.seedGame({ users, gameMode: 'treachery' });
      await game.host.call('updateGameSettings', { gameId: game.gameId, gameMode: mode });
      const g = await h.getGame(game.gameId);
      assert.equal(g.game_mode, mode);
    });
  }

  it('rejects an unknown mode', async () => {
    const users = await h.getUsers(2);
    const game = await h.seedGame({ users, gameMode: 'treachery' });
    await h.expectHttpsError(
      game.host.call('updateGameSettings', { gameId: game.gameId, gameMode: 'chess' }),
      'invalid-argument'
    );
    const g = await h.getGame(game.gameId);
    assert.equal(g.game_mode, 'treachery');
  });
});

describe('updateGameSettings — startingLife', () => {
  for (const bad of [35, 0, 41, -20]) {
    it(`rejects the unsupported value ${bad}`, async () => {
      const users = await h.getUsers(3);
      const game = await h.seedGame({ users, startingLife: 40 });
      await h.expectHttpsError(
        game.host.call('updateGameSettings', { gameId: game.gameId, startingLife: bad }),
        'invalid-argument'
      );
      const g = await h.getGame(game.gameId);
      assert.equal(g.starting_life, 40);
    });
  }

  // SKIP: currently broken — see finding #A. Un-skip when functions/index.js is fixed.
  //
  // index.js ~1483 writes with `tx.update(gameRef, update)` and then reads the
  // players subcollection at ~1487. Firestore transactions require every read
  // to precede every write, so the SDK throws and the whole transaction is
  // rolled back: passing startingLife ALWAYS fails with `internal`.
  for (const life of [20, 25, 30, 50]) {
    it(
      `sets starting_life to ${life} and re-bases every player's life_total`,
      { skip: 'currently broken — see finding #A' },
      async () => {
        const users = await h.getUsers(3);
        const game = await h.seedGame({ users, startingLife: 40 });

        const res = await game.host.call('updateGameSettings', {
          gameId: game.gameId,
          startingLife: life,
        });
        assert.deepEqual(res, { success: true });

        const g = await h.getGame(game.gameId);
        assert.equal(g.starting_life, life);

        const players = await h.getPlayers(game.gameId);
        assert.equal(players.length, 3);
        for (const p of players) {
          assert.equal(p.life_total, life, `${p.id} life_total must follow starting_life`);
        }
      }
    );
  }

  // SKIP: currently broken — see finding #A. Un-skip when functions/index.js is fixed.
  //
  // Because the transaction throws, any setting co-submitted with startingLife
  // is rolled back too — a host changing life + max players in one save loses
  // BOTH changes.
  it(
    'persists every setting co-submitted with startingLife',
    { skip: 'currently broken — see finding #A' },
    async () => {
      const users = await h.getUsers(3);
      const game = await h.seedGame({
        users,
        startingLife: 40,
        maxPlayers: 8,
        gameMode: 'treachery',
      });

      await game.host.call('updateGameSettings', {
        gameId: game.gameId,
        startingLife: 25,
        maxPlayers: 5,
        gameMode: 'treachery_planechase',
        maxTraitorRarity: 'rare',
      });

      const g = await h.getGame(game.gameId);
      assert.equal(g.starting_life, 25);
      assert.equal(g.max_players, 5);
      assert.equal(g.game_mode, 'treachery_planechase');
      assert.equal(g.max_traitor_rarity, 'rare');

      const players = await h.getPlayers(game.gameId);
      for (const p of players) assert.equal(p.life_total, 25);
    }
  );

  // SKIP: currently broken — see finding #A. Un-skip when functions/index.js is fixed.
  //
  // The re-based starting life must be what startGame deals out.
  it(
    'a startingLife change is reflected in the life totals startGame deals',
    { skip: 'currently broken — see finding #A' },
    async () => {
      const users = await h.getUsers(4);
      const game = await h.seedGame({ users, startingLife: 40 });

      await game.host.call('updateGameSettings', { gameId: game.gameId, startingLife: 30 });
      await game.host.call('startGame', { gameId: game.gameId });

      const players = await h.getPlayers(game.gameId);
      for (const p of players) {
        const card = h.cardById(p.identity_card_id);
        assert.equal(p.life_total, 30 + (card.life_modifier || 0));
      }
    }
  );
});
