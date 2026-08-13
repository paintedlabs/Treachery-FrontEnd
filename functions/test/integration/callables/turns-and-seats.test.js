'use strict';

/**
 * INTEGRATION: exports.setActivePlayer / advanceTurn / reorderSeats
 * (functions/index.js)
 *
 * The server half of the Round Table board: whose turn it is, and the seating
 * order players drag tiles into. Both are shared state on purpose — a turn
 * marker or seat ring that differed per client would be worse than none.
 */

const { describe, it, after } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

after(async () => {
  await h.shutdown();
});

/** Player doc ids in seat order (order_id ascending). */
async function seatIds(gameId) {
  const players = await h.getPlayers(gameId);
  return players
    .slice()
    .sort((a, b) => a.order_id - b.order_id)
    .map((p) => p.id);
}

/**
 * A valid role/card layout for `count` players — seedStartedGame needs the
 * assignments to match getRoleDistribution exactly or startGame rejects them.
 * These tests don't care which role sits where, only about seats and turns.
 */
function seatsFor(count) {
  const dist = h.EXPECTED_DISTRIBUTION[count];
  if (!dist) throw new Error(`No distribution for ${count} players`);
  const seats = [];
  for (const role of ['leader', 'guardian', 'assassin', 'traitor']) {
    for (let i = 0; i < dist[role]; i++) {
      seats.push({ role, card: `${role}_${String(seats.filter((s) => s.role === role).length + 1).padStart(2, '0')}` });
    }
  }
  return seats;
}

/** seedStartedGame with an auto-built legal role layout. */
function startGameFor(users) {
  return h.seedStartedGame({ users, seats: seatsFor(users.length), startingLife: 40 });
}

describe('startGame seeds the turn marker', () => {
  it('sets active_player_id to the first seat', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);
    const g = await h.getGame(game.gameId);
    assert.equal(g.active_player_id, seats[0]);
  });
});

describe('setActivePlayer', () => {
  it('lets any player at the table set the turn', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);

    // users[2], not the host — this is a shared table, not a host-run session.
    await users[2].call('setActivePlayer', { gameId: game.gameId, playerId: seats[3] });
    assert.equal((await h.getGame(game.gameId)).active_player_id, seats[3]);
  });

  it('clears the marker when passed null', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    await users[0].call('setActivePlayer', { gameId: game.gameId, playerId: null });
    assert.equal((await h.getGame(game.gameId)).active_player_id, null);
  });

  it('rejects a non-participant', async () => {
    const users = await h.getUsers(5);
    const game = await startGameFor(users.slice(0, 4));
    const seats = await seatIds(game.gameId);
    await h.expectHttpsError(
      users[4].call('setActivePlayer', { gameId: game.gameId, playerId: seats[0] }),
      'permission-denied'
    );
  });

  it('rejects an unknown player id', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    await h.expectHttpsError(
      users[0].call('setActivePlayer', { gameId: game.gameId, playerId: 'not-a-player' }),
      'not-found'
    );
  });

  it('refuses to hand the turn to an eliminated player', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);
    await h.patchPlayer(game.gameId, seats[2], { is_eliminated: true, life_total: 0 });
    await h.expectHttpsError(
      users[0].call('setActivePlayer', { gameId: game.gameId, playerId: seats[2] }),
      'failed-precondition'
    );
  });
});

describe('advanceTurn', () => {
  it('moves to the next seat', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);

    await users[0].call('setActivePlayer', { gameId: game.gameId, playerId: seats[0] });
    await users[0].call('advanceTurn', { gameId: game.gameId });
    assert.equal((await h.getGame(game.gameId)).active_player_id, seats[1]);
  });

  it('wraps around from the last seat to the first', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);

    await users[0].call('setActivePlayer', { gameId: game.gameId, playerId: seats[3] });
    await users[0].call('advanceTurn', { gameId: game.gameId });
    assert.equal((await h.getGame(game.gameId)).active_player_id, seats[0]);
  });

  it('skips eliminated players', async () => {
    const users = await h.getUsers(5);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);

    await h.patchPlayer(game.gameId, seats[1], { is_eliminated: true, life_total: 0 });
    await h.patchPlayer(game.gameId, seats[2], { is_eliminated: true, life_total: 0 });

    await users[0].call('setActivePlayer', { gameId: game.gameId, playerId: seats[0] });
    await users[0].call('advanceTurn', { gameId: game.gameId });
    assert.equal(
      (await h.getGame(game.gameId)).active_player_id,
      seats[3],
      'should jump past both eliminated seats'
    );
  });

  it('advances to the first living seat when no turn is set', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);

    await users[0].call('setActivePlayer', { gameId: game.gameId, playerId: null });
    await users[0].call('advanceTurn', { gameId: game.gameId });
    assert.equal((await h.getGame(game.gameId)).active_player_id, seats[0]);
  });

  it('stays on the sole survivor rather than stalling', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);
    for (const id of seats.slice(1)) {
      await h.patchPlayer(game.gameId, id, { is_eliminated: true, life_total: 0 });
    }
    await users[0].call('setActivePlayer', { gameId: game.gameId, playerId: seats[0] });
    await users[0].call('advanceTurn', { gameId: game.gameId });
    assert.equal((await h.getGame(game.gameId)).active_player_id, seats[0]);
  });

  it('clears the marker when everyone is eliminated', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);
    for (const id of seats) {
      await h.patchPlayer(game.gameId, id, { is_eliminated: true, life_total: 0 });
    }
    await users[0].call('advanceTurn', { gameId: game.gameId });
    assert.equal((await h.getGame(game.gameId)).active_player_id, null);
  });

  it('rejects a non-participant', async () => {
    const users = await h.getUsers(5);
    const game = await startGameFor(users.slice(0, 4));
    await h.expectHttpsError(
      users[4].call('advanceTurn', { gameId: game.gameId }),
      'permission-denied'
    );
  });
});

describe('reorderSeats', () => {
  it('rewrites order_id to the supplied seating', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);
    const shuffled = [seats[2], seats[0], seats[3], seats[1]];

    await users[1].call('reorderSeats', { gameId: game.gameId, orderedPlayerIds: shuffled });
    assert.deepEqual(await seatIds(game.gameId), shuffled);
  });

  it('always writes a contiguous 0..N-1 run', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);

    await users[0].call('reorderSeats', { gameId: game.gameId, orderedPlayerIds: seats });
    const players = await h.getPlayers(game.gameId);
    const ids = players.map((p) => p.order_id).sort((a, b) => a - b);
    assert.deepEqual(ids, [0, 1, 2, 3]);
  });

  it('repairs duplicate order_ids left in a broken ring', async () => {
    // Simulate a corrupt ring (duplicate order_id). Reordering must
    // rewrite a contiguous 0..N-1 run regardless of how it got that way.
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);
    await h.patchPlayer(game.gameId, seats[3], { order_id: 2 }); // collide with seats[2]

    await users[0].call('reorderSeats', { gameId: game.gameId, orderedPlayerIds: seats });
    const players = await h.getPlayers(game.gameId);
    const ids = players.map((p) => p.order_id).sort((a, b) => a - b);
    assert.deepEqual(ids, [0, 1, 2, 3], 'duplicates must be gone');
  });

  it('rejects a list that drops a player', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);
    await h.expectHttpsError(
      users[0].call('reorderSeats', { gameId: game.gameId, orderedPlayerIds: seats.slice(1) }),
      'invalid-argument'
    );
  });

  it('rejects duplicate ids', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);
    await h.expectHttpsError(
      users[0].call('reorderSeats', {
        gameId: game.gameId,
        orderedPlayerIds: [seats[0], seats[0], seats[1], seats[2]],
      }),
      'invalid-argument'
    );
  });

  it('rejects an id that is not a seat in this game', async () => {
    // Note there is deliberately no "id smuggled from another game" test:
    // player docs live at games/{gameId}/players/{id}, so the gameId already
    // scopes every write. An id from elsewhere either also names a real seat
    // here (in which case reordering it is legitimate) or doesn't exist and is
    // caught below. The harness even seeds both games with the same ids
    // (p0..p3), which makes the cross-game framing meaningless.
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);
    await h.expectHttpsError(
      users[0].call('reorderSeats', {
        gameId: game.gameId,
        orderedPlayerIds: ['no-such-player', seats[1], seats[2], seats[3]],
      }),
      'invalid-argument'
    );
  });

  it('rejects a non-string seat id', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);
    await h.expectHttpsError(
      users[0].call('reorderSeats', {
        gameId: game.gameId,
        orderedPlayerIds: [42, seats[1], seats[2], seats[3]],
      }),
      'invalid-argument'
    );
  });

  it('rejects a non-participant', async () => {
    const users = await h.getUsers(5);
    const game = await startGameFor(users.slice(0, 4));
    const seats = await seatIds(game.gameId);
    await h.expectHttpsError(
      users[4].call('reorderSeats', { gameId: game.gameId, orderedPlayerIds: seats }),
      'permission-denied'
    );
  });

  it('leaves the turn marker pointing at the same player after a reorder', async () => {
    // The marker stores a player doc id, not a seat index, precisely so that
    // dragging seats around doesn't silently hand the turn to someone else.
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);

    await users[0].call('setActivePlayer', { gameId: game.gameId, playerId: seats[1] });
    await users[0].call('reorderSeats', {
      gameId: game.gameId,
      orderedPlayerIds: [seats[3], seats[1], seats[0], seats[2]],
    });
    assert.equal((await h.getGame(game.gameId)).active_player_id, seats[1]);
  });

  it('rejects a reorder after the game has finished', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);
    await h.patchGame(game.gameId, { state: 'finished', winning_team: 'leader' });
    await h.expectHttpsError(
      users[0].call('reorderSeats', { gameId: game.gameId, orderedPlayerIds: seats }),
      'failed-precondition'
    );
  });
});

describe('elimination advances a stale turn marker', () => {
  it('forfeit of the active player hands the turn to the next living seat', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);

    // Seat 0 is the leader (seatsFor layout). Forfeiting them would end the
    // game. Put the turn on the first assassin and have them forfeit instead.
    await users[0].call('setActivePlayer', { gameId: game.gameId, playerId: seats[1] });
    await users[1].call('eliminatePlayer', { gameId: game.gameId });

    const g = await h.getGame(game.gameId);
    assert.equal(g.state, 'in_progress');
    assert.equal(g.active_player_id, seats[2]);
  });

  it('life-to-zero of the active player also advances the turn', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);

    await users[0].call('setActivePlayer', { gameId: game.gameId, playerId: seats[1] });
    await users[0].call('adjustLife', { gameId: game.gameId, playerId: seats[1], amount: -40 });

    const g = await h.getGame(game.gameId);
    assert.equal(g.state, 'in_progress');
    assert.equal(g.active_player_id, seats[2]);
    assert.equal((await h.getPlayer(game.gameId, seats[1])).is_eliminated, true);
  });

  it('eliminating a non-active player leaves the marker alone', async () => {
    const users = await h.getUsers(4);
    const game = await startGameFor(users);
    const seats = await seatIds(game.gameId);

    await users[0].call('setActivePlayer', { gameId: game.gameId, playerId: seats[0] });
    await users[2].call('eliminatePlayer', { gameId: game.gameId });

    assert.equal((await h.getGame(game.gameId)).active_player_id, seats[0]);
  });
});
