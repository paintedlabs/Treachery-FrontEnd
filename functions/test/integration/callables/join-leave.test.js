'use strict';

/**
 * INTEGRATION: exports.joinGame and exports.leaveGame (functions/index.js)
 */

const { describe, it, after } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

after(async () => {
  await h.shutdown();
});

describe('joinGame', () => {
  it('adds the caller to a waiting lobby and is case-insensitive on the code', async () => {
    const users = await h.getUsers(2);
    const game = await h.seedGame({ users: [users[0]], maxPlayers: 8, startingLife: 30 });

    const res = await users[1].call('joinGame', { gameCode: game.code.toLowerCase() });
    assert.equal(res.action, 'joined');
    assert.equal(res.gameId, game.gameId);

    const players = await h.getPlayers(game.gameId);
    assert.equal(players.length, 2);
    const joined = players.find((p) => p.user_id === users[1].uid);
    assert.ok(joined, 'a player doc must be created for the joiner');
    assert.equal(joined.order_id, 1, 'order_id follows the current player count');
    assert.equal(joined.display_name, users[1].displayName);
    assert.equal(joined.life_total, 30, "life_total seeds from the game's starting life");
    assert.equal(joined.role, null);
    assert.equal(joined.is_eliminated, false);

    const g = await h.getGame(game.gameId);
    assert.ok(g.player_ids.includes(users[1].uid), 'player_ids must include the joiner');
  });

  it('is idempotent for a player who is already in the game', async () => {
    const users = await h.getUsers(2);
    const game = await h.seedGame({ users });

    const res = await users[1].call('joinGame', { gameCode: game.code });
    assert.equal(res.action, 'already_joined');
    assert.equal(res.gameId, game.gameId);

    const players = await h.getPlayers(game.gameId);
    assert.equal(players.length, 2, 'no duplicate player doc');
  });

  it('enforces the lobby capacity', async () => {
    const users = await h.getUsers(3);
    const game = await h.seedGame({ users: users.slice(0, 2), maxPlayers: 2 });

    await h.expectHttpsError(
      users[2].call('joinGame', { gameCode: game.code }),
      'failed-precondition'
    );

    const players = await h.getPlayers(game.gameId);
    assert.equal(players.length, 2, 'a rejected join must not create a player doc');
    const g = await h.getGame(game.gameId);
    assert.ok(!g.player_ids.includes(users[2].uid));
  });

  it('rejects joining a game that is already in progress', async () => {
    const users = await h.getUsers(5);
    const game = await h.seedGame({ users: users.slice(0, 4) });
    await game.host.call('startGame', { gameId: game.gameId });

    await h.expectHttpsError(
      users[4].call('joinGame', { gameCode: game.code }),
      'failed-precondition'
    );
    const players = await h.getPlayers(game.gameId);
    assert.equal(players.length, 4);
  });

  it('rejects an unknown game code', async () => {
    const [user] = await h.getUsers(1);
    await h.expectHttpsError(
      user.call('joinGame', { gameCode: 'ZZZZZZ' }),
      'not-found'
    );
  });

  it('rejects a missing game code', async () => {
    const [user] = await h.getUsers(1);
    await h.expectHttpsError(user.call('joinGame', {}), 'invalid-argument');
  });

  it('rejects an unauthenticated caller', async () => {
    const users = await h.getUsers(1);
    const game = await h.seedGame({ users });
    await h.expectHttpsError(
      h.unauthenticatedCaller()('joinGame', { gameCode: game.code }),
      'unauthenticated'
    );
  });
});

describe('leaveGame', () => {
  it('promotes the next player to host when the host leaves a non-empty lobby', async () => {
    const users = await h.getUsers(3);
    const game = await h.seedGame({ users });

    const res = await game.host.call('leaveGame', { gameId: game.gameId });
    assert.equal(res.action, 'promoted');
    assert.equal(res.newHostId, users[1].uid, 'lowest remaining order_id becomes host');

    const g = await h.getGame(game.gameId);
    assert.ok(g, 'the game must survive the host leaving');
    assert.equal(g.host_id, users[1].uid);
    assert.deepEqual(g.player_ids, [users[1].uid, users[2].uid]);

    const players = await h.getPlayers(game.gameId);
    assert.equal(players.length, 2);
    assert.ok(!players.some((p) => p.user_id === users[0].uid));
  });

  it('deletes the game when the last player leaves', async () => {
    const users = await h.getUsers(1);
    const game = await h.seedGame({ users });

    const res = await game.host.call('leaveGame', { gameId: game.gameId });
    assert.equal(res.action, 'deleted');

    const g = await h.getGame(game.gameId);
    assert.equal(g, null, 'the game doc must be removed');
  });

  it('removes a non-host without changing the host', async () => {
    const users = await h.getUsers(3);
    const game = await h.seedGame({ users });

    const res = await users[1].call('leaveGame', { gameId: game.gameId });
    assert.equal(res.action, 'left');

    const g = await h.getGame(game.gameId);
    assert.equal(g.host_id, users[0].uid);
    assert.deepEqual(g.player_ids, [users[0].uid, users[2].uid]);

    const players = await h.getPlayers(game.gameId);
    assert.equal(players.length, 2);
    assert.ok(!players.some((p) => p.user_id === users[1].uid));
  });

  it('rejects leaving a game that is in progress', async () => {
    const users = await h.getUsers(4);
    const game = await h.seedGame({ users });
    await game.host.call('startGame', { gameId: game.gameId });

    await h.expectHttpsError(
      users[1].call('leaveGame', { gameId: game.gameId }),
      'failed-precondition'
    );
    const players = await h.getPlayers(game.gameId);
    assert.equal(players.length, 4);
  });

  it('rejects a caller who is not in the game', async () => {
    const users = await h.getUsers(3);
    const game = await h.seedGame({ users: users.slice(0, 2) });
    await h.expectHttpsError(
      users[2].call('leaveGame', { gameId: game.gameId }),
      'not-found'
    );
  });

  it('rejects an unknown gameId', async () => {
    const [user] = await h.getUsers(1);
    await h.expectHttpsError(
      user.call('leaveGame', { gameId: 'nope' }),
      'not-found'
    );
  });

  // SKIP: currently broken — see finding #G. Un-skip when functions/index.js is fixed.
  //
  // leaveGame deletes the player doc but never renumbers the survivors, while
  // joinGame derives the new seat as `orderId = existingPlayers.length`. So
  // after anyone but the last player leaves, the next joiner collides with an
  // existing order_id: seats 0,1,2 minus seat 1 leaves 0,2 (length 2), and the
  // joiner is also given 2. Two players then share a seat number, which makes
  // every `orderBy("order_id")` read (startGame, adjustLife, leaveGame's own
  // host promotion) non-deterministic.
  it(
    'keeps order_id unique after a middle player leaves and a new one joins',
    { skip: 'currently broken — see finding #G' },
    async () => {
      const users = await h.getUsers(4);
      const game = await h.seedGame({ users: users.slice(0, 3), maxPlayers: 8 });

      await users[1].call('leaveGame', { gameId: game.gameId });
      await users[3].call('joinGame', { gameCode: game.code });

      const players = await h.getPlayers(game.gameId);
      assert.equal(players.length, 3);
      const orderIds = players.map((p) => p.order_id);
      assert.equal(
        new Set(orderIds).size,
        orderIds.length,
        `order_id must stay unique, got ${orderIds.join(', ')}`
      );
    }
  );

  it('rejects an unauthenticated caller', async () => {
    const users = await h.getUsers(2);
    const game = await h.seedGame({ users });
    await h.expectHttpsError(
      h.unauthenticatedCaller()('leaveGame', { gameId: game.gameId }),
      'unauthenticated'
    );
  });
});
