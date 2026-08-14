'use strict';

/**
 * INTEGRATION: exports.startGame (functions/index.js)
 *
 * Drives the real callable against the emulator: seeds a lobby with
 * firebase-admin, signs in as the host with the client SDK, invokes
 * startGame, and asserts on the Firestore state it produced.
 */

const { describe, it, after } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

after(async () => {
  await h.shutdown();
});

describe('startGame — treachery role & card assignment', () => {
  for (const count of [4, 5, 6, 7, 8]) {
    it(`assigns the documented role distribution for ${count} players`, async () => {
      const users = await h.getUsers(count);
      const game = await h.seedGame({ users, startingLife: 40 });

      const res = await game.host.call('startGame', { gameId: game.gameId });
      assert.deepEqual(res, { success: true });

      const players = await h.getPlayers(game.gameId);
      assert.equal(players.length, count);
      assert.deepEqual(
        h.roleCounts(players),
        h.EXPECTED_DISTRIBUTION[count],
        `role distribution for ${count} players`
      );

      const cardIds = players.map((p) => p.identity_card_id);
      assert.equal(
        new Set(cardIds).size,
        count,
        `identity cards must be unique, got ${cardIds.join(', ')}`
      );

      for (const p of players) {
        const card = h.cardById(p.identity_card_id);
        assert.ok(card, `unknown identity card ${p.identity_card_id}`);
        assert.equal(card.role, p.role, `card ${card.id} must match assigned role`);
        assert.equal(
          p.life_total,
          40 + (card.life_modifier || 0),
          `life_total for ${card.id} (life_modifier ${card.life_modifier})`
        );
      }

      const g = await h.getGame(game.gameId);
      assert.equal(g.state, 'in_progress');
      assert.ok(g.last_activity_at, 'last_activity_at must be stamped');
    });
  }

  it('applies the card life_modifier on top of a non-default starting life', async () => {
    const users = await h.getUsers(4);
    // leader_10 (The Old Ruler) is the only card with a life_modifier (+20).
    const game = await h.seedStartedGame({
      users,
      startingLife: 25,
      seats: [
        { role: 'leader', card: 'leader_10' },
        { role: 'assassin', card: 'assassin_01' },
        { role: 'assassin', card: 'assassin_02' },
        { role: 'traitor', card: 'traitor_01' },
      ],
    });

    const players = await h.getPlayers(game.gameId);
    assert.equal(players[0].life_total, 45, 'leader_10 = 25 starting life + 20 modifier');
    assert.equal(players[1].life_total, 25);
    assert.equal(players[2].life_total, 25);
    assert.equal(players[3].life_total, 25);
  });
});

describe('startGame — authorisation & preconditions', () => {
  it('rejects a non-host with permission-denied', async () => {
    const users = await h.getUsers(4);
    const game = await h.seedGame({ users });
    await h.expectHttpsError(
      users[1].call('startGame', { gameId: game.gameId }),
      'permission-denied'
    );
    const g = await h.getGame(game.gameId);
    assert.equal(g.state, 'waiting', 'a rejected start must not change game state');
  });

  it('rejects starting a game that is already in progress', async () => {
    const users = await h.getUsers(4);
    const game = await h.seedGame({ users });
    await game.host.call('startGame', { gameId: game.gameId });
    await h.expectHttpsError(
      game.host.call('startGame', { gameId: game.gameId }),
      'failed-precondition'
    );
  });

  it('rejects an unauthenticated caller', async () => {
    const users = await h.getUsers(4);
    const game = await h.seedGame({ users });
    await h.expectHttpsError(
      h.unauthenticatedCaller()('startGame', { gameId: game.gameId }),
      'unauthenticated'
    );
  });

  it('rejects a missing gameId', async () => {
    const [host] = await h.getUsers(1);
    await h.expectHttpsError(host.call('startGame', {}), 'invalid-argument');
  });

  it('rejects an unknown gameId', async () => {
    const [host] = await h.getUsers(1);
    await h.expectHttpsError(
      host.call('startGame', { gameId: 'does-not-exist' }),
      'not-found'
    );
  });
});

describe('startGame — testSeed validation (emulator-only hook)', () => {
  it('rejects a seed whose role counts do not match the distribution', async () => {
    const users = await h.getUsers(4);
    const game = await h.seedGame({ users });
    const assignments = {};
    // 2 leaders / 1 assassin / 1 traitor — not the 4-player distribution.
    const bad = [
      { role: 'leader', card: 'leader_01' },
      { role: 'leader', card: 'leader_02' },
      { role: 'assassin', card: 'assassin_01' },
      { role: 'traitor', card: 'traitor_01' },
    ];
    users.forEach((u, i) => {
      assignments[u.uid] = { role: bad[i].role, identityCardId: bad[i].card };
    });
    await h.expectHttpsError(
      game.host.call('startGame', { gameId: game.gameId, testSeed: { assignments } }),
      'invalid-argument'
    );
  });

  it('rejects a seed where a card does not match its declared role', async () => {
    const users = await h.getUsers(4);
    const game = await h.seedGame({ users });
    const assignments = {};
    const bad = [
      { role: 'leader', card: 'leader_01' },
      { role: 'assassin', card: 'assassin_01' },
      { role: 'assassin', card: 'guardian_01' }, // wrong role for the card
      { role: 'traitor', card: 'traitor_01' },
    ];
    users.forEach((u, i) => {
      assignments[u.uid] = { role: bad[i].role, identityCardId: bad[i].card };
    });
    await h.expectHttpsError(
      game.host.call('startGame', { gameId: game.gameId, testSeed: { assignments } }),
      'invalid-argument'
    );
  });

  it('rejects a seed that hands the same card to two players', async () => {
    const users = await h.getUsers(4);
    const game = await h.seedGame({ users });
    const assignments = {};
    const bad = [
      { role: 'leader', card: 'leader_01' },
      { role: 'assassin', card: 'assassin_01' },
      { role: 'assassin', card: 'assassin_01' },
      { role: 'traitor', card: 'traitor_01' },
    ];
    users.forEach((u, i) => {
      assignments[u.uid] = { role: bad[i].role, identityCardId: bad[i].card };
    });
    await h.expectHttpsError(
      game.host.call('startGame', { gameId: game.gameId, testSeed: { assignments } }),
      'invalid-argument'
    );
  });
});

describe('startGame — non-treachery game modes', () => {
  for (const mode of ['none', 'planechase']) {
    it(`"${mode}" starts without assigning roles or identity cards`, async () => {
      const users = await h.getUsers(4);
      const game = await h.seedGame({ users, gameMode: mode, startingLife: 30 });

      await game.host.call('startGame', { gameId: game.gameId });

      const players = await h.getPlayers(game.gameId);
      for (const p of players) {
        assert.equal(p.role, null, 'no roles in a non-treachery game');
        assert.equal(p.identity_card_id, null, 'no identity cards in a non-treachery game');
        assert.equal(p.life_total, 30);
      }
      const g = await h.getGame(game.gameId);
      assert.equal(g.state, 'in_progress');
    });
  }

  it('planechase mode seeds a starting plane', async () => {
    const users = await h.getUsers(4);
    const game = await h.seedGame({ users, gameMode: 'planechase' });
    await game.host.call('startGame', { gameId: game.gameId });
    const g = await h.getGame(game.gameId);
    assert.ok(g.planechase, 'planechase state must be initialised');
    assert.ok(g.planechase.current_plane_id, 'a starting plane must be chosen');
    assert.deepEqual(g.planechase.used_plane_ids, [g.planechase.current_plane_id]);
    assert.equal(g.planechase.chaotic_aether_active, false);
  });
});

describe('startGame — player counts outside the distribution table', () => {
  it('rejects a 9-player start with a clear client error', async () => {
    const users = await h.getUsers(9);
    const game = await h.seedGame({ users, maxPlayers: 8 });

    await h.expectHttpsError(
      game.host.call('startGame', { gameId: game.gameId }),
      'failed-precondition'
    );
    const g = await h.getGame(game.gameId);
    assert.equal(g.state, 'waiting', 'a failed start must roll back');
  });
});

describe('startGame — player_ids reconciliation (ghost spectators)', () => {
  // The append-self rules path lets any signed-in user add their uid to a
  // waiting game's player_ids without creating a player doc. player_ids gates
  // player-doc reads, so an unreconciled ghost would read every role and
  // identity card the moment the deal writes them. startGame must rebuild the
  // array from the players actually seated.
  it('evicts a player_ids entry that has no seated player doc', async () => {
    const users = await h.getUsers(5);
    const seated = users.slice(0, 4);
    const ghost = users[4];

    // Seed the exact post-attack state: ghost uid in the array, no player doc.
    const game = await h.seedGame({
      users: seated,
      gameFields: { player_ids: [...seated.map((u) => u.uid), ghost.uid] },
    });

    const res = await game.host.call('startGame', { gameId: game.gameId });
    assert.deepEqual(res, { success: true });

    const g = await h.getGame(game.gameId);
    assert.deepEqual(
      [...g.player_ids].sort(),
      seated.map((u) => u.uid).sort(),
      'player_ids must contain exactly the seated players after the deal'
    );
    assert.ok(!g.player_ids.includes(ghost.uid), 'ghost uid must be evicted');

    // The seated players all made it through untouched — a legitimate legacy
    // direct-join (array append + player doc create) must survive reconcile.
    const players = await h.getPlayers(game.gameId);
    assert.equal(players.length, 4);
    for (const p of players) {
      assert.ok(g.player_ids.includes(p.user_id), `${p.user_id} must keep list membership`);
    }
  });
});
