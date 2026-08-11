'use strict';

/**
 * INTEGRATION: exports.adjustLife (functions/index.js) and, through it, the
 * win-condition engine that runs when a player is eliminated.
 */

const { describe, it, after } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

after(async () => {
  await h.shutdown();
});

/** leader / assassin / assassin / traitor — the documented 4-player layout. */
const SEATS_4P = [
  { role: 'leader', card: 'leader_01' },
  { role: 'assassin', card: 'assassin_01' },
  { role: 'assassin', card: 'assassin_02' },
  { role: 'traitor', card: 'traitor_01' },
];

/** leader / guardian / assassin / assassin / traitor. */
const SEATS_5P = [
  { role: 'leader', card: 'leader_01' },
  { role: 'guardian', card: 'guardian_01' },
  { role: 'assassin', card: 'assassin_01' },
  { role: 'assassin', card: 'assassin_02' },
  { role: 'traitor', card: 'traitor_01' },
];

async function startedTreacheryGame(seats) {
  const users = await h.getUsers(seats.length);
  return h.seedStartedGame({ users, seats, startingLife: 40 });
}

describe('adjustLife — arithmetic & elimination', () => {
  it('subtracts life without eliminating while life remains', async () => {
    const game = await startedTreacheryGame(SEATS_4P);
    const res = await game.users[1].call('adjustLife', {
      gameId: game.gameId,
      playerId: 'p1',
      amount: -13,
    });
    assert.equal(res.newLife, 27);
    assert.equal(res.eliminated, false);
    assert.equal(res.winner, null);

    const p = await h.getPlayer(game.gameId, 'p1');
    assert.equal(p.life_total, 27);
    assert.equal(p.is_eliminated, false);
    assert.equal(p.is_unveiled, false);
  });

  it('adds life too', async () => {
    const game = await startedTreacheryGame(SEATS_4P);
    const res = await game.users[0].call('adjustLife', {
      gameId: game.gameId,
      playerId: 'p1',
      amount: 5,
    });
    assert.equal(res.newLife, 45);
    assert.equal(res.eliminated, false);
  });

  it('eliminates and unveils a player who lands on exactly 0', async () => {
    const game = await startedTreacheryGame(SEATS_4P);
    const res = await game.users[1].call('adjustLife', {
      gameId: game.gameId,
      playerId: 'p1',
      amount: -40,
    });
    assert.equal(res.newLife, 0);
    assert.equal(res.eliminated, true);

    const p = await h.getPlayer(game.gameId, 'p1');
    assert.equal(p.life_total, 0);
    assert.equal(p.is_eliminated, true);
    assert.equal(p.is_unveiled, true, 'elimination reveals the identity');
  });

  it('clamps overkill damage to 0 rather than storing a negative life total', async () => {
    const game = await startedTreacheryGame(SEATS_4P);
    const res = await game.users[1].call('adjustLife', {
      gameId: game.gameId,
      playerId: 'p1',
      amount: -1000,
    });
    assert.equal(res.newLife, 0);
    assert.equal(res.eliminated, true);

    const p = await h.getPlayer(game.gameId, 'p1');
    assert.equal(p.life_total, 0, 'life must never go below zero');
  });
});

describe('adjustLife — authorisation & preconditions', () => {
  it('rejects a caller who is not in the game', async () => {
    const users = await h.getUsers(5);
    const game = await h.seedStartedGame({
      users: users.slice(0, 4),
      seats: SEATS_4P,
    });
    const outsider = users[4];
    await h.expectHttpsError(
      outsider.call('adjustLife', { gameId: game.gameId, playerId: 'p1', amount: -5 }),
      'permission-denied'
    );
    const p = await h.getPlayer(game.gameId, 'p1');
    assert.equal(p.life_total, 40, 'a rejected adjustment must not persist');
  });

  it('rejects editing an already-eliminated player', async () => {
    const game = await startedTreacheryGame(SEATS_4P);
    await game.users[1].call('adjustLife', {
      gameId: game.gameId,
      playerId: 'p1',
      amount: -40,
    });
    await h.expectHttpsError(
      game.users[1].call('adjustLife', { gameId: game.gameId, playerId: 'p1', amount: 5 }),
      'failed-precondition'
    );
  });

  it('rejects adjustments while the game is still waiting', async () => {
    const users = await h.getUsers(4);
    const game = await h.seedGame({ users });
    await h.expectHttpsError(
      game.host.call('adjustLife', { gameId: game.gameId, playerId: 'p0', amount: -1 }),
      'failed-precondition'
    );
  });

  it('rejects a non-integer amount', async () => {
    const game = await startedTreacheryGame(SEATS_4P);
    await h.expectHttpsError(
      game.users[0].call('adjustLife', { gameId: game.gameId, playerId: 'p1', amount: 1.5 }),
      'invalid-argument'
    );
    await h.expectHttpsError(
      game.users[0].call('adjustLife', { gameId: game.gameId, playerId: 'p1', amount: '-5' }),
      'invalid-argument'
    );
  });

  it('rejects a missing amount', async () => {
    const game = await startedTreacheryGame(SEATS_4P);
    await h.expectHttpsError(
      game.users[0].call('adjustLife', { gameId: game.gameId, playerId: 'p1' }),
      'invalid-argument'
    );
  });

  it('rejects an unknown player id', async () => {
    const game = await startedTreacheryGame(SEATS_4P);
    await h.expectHttpsError(
      game.users[0].call('adjustLife', { gameId: game.gameId, playerId: 'nope', amount: -1 }),
      'not-found'
    );
  });

  it('rejects an unauthenticated caller', async () => {
    const game = await startedTreacheryGame(SEATS_4P);
    await h.expectHttpsError(
      h.unauthenticatedCaller()('adjustLife', {
        gameId: game.gameId,
        playerId: 'p1',
        amount: -1,
      }),
      'unauthenticated'
    );
  });
});

describe('adjustLife — treachery win conditions', () => {
  it('assassins win the moment the Leader is eliminated', async () => {
    const game = await startedTreacheryGame(SEATS_4P);
    const res = await game.users[1].call('adjustLife', {
      gameId: game.gameId,
      playerId: 'p0',
      amount: -40,
    });
    assert.equal(res.winner, 'assassin');

    const g = await h.getGame(game.gameId);
    assert.equal(g.state, 'finished');
    assert.equal(g.winning_team, 'assassin');
  });

  it('the Leader wins once every assassin and traitor is out', async () => {
    const game = await startedTreacheryGame(SEATS_4P);
    const kill = (playerId) =>
      game.users[0].call('adjustLife', { gameId: game.gameId, playerId, amount: -40 });

    assert.equal((await kill('p3')).winner, null, 'traitor out — game continues');
    assert.equal((await kill('p1')).winner, null, 'one assassin left — game continues');
    assert.equal((await kill('p2')).winner, 'leader');

    const g = await h.getGame(game.gameId);
    assert.equal(g.state, 'finished');
    assert.equal(g.winning_team, 'leader');
  });

  it('a surviving Guardian counts towards the Leader win', async () => {
    const game = await startedTreacheryGame(SEATS_5P);
    const kill = (playerId) =>
      game.users[0].call('adjustLife', { gameId: game.gameId, playerId, amount: -40 });

    assert.equal((await kill('p4')).winner, null, 'traitor out');
    assert.equal((await kill('p2')).winner, null, 'one assassin left');
    assert.equal((await kill('p3')).winner, 'leader');

    const players = await h.getPlayers(game.gameId);
    const guardian = players.find((p) => p.role === 'guardian');
    assert.equal(guardian.is_eliminated, false, 'the guardian survived');

    const g = await h.getGame(game.gameId);
    assert.equal(g.winning_team, 'leader');
  });

  it('the traitor wins by being the last player standing', async () => {
    const game = await startedTreacheryGame(SEATS_4P);
    const kill = (playerId) =>
      game.users[3].call('adjustLife', { gameId: game.gameId, playerId, amount: -40 });

    assert.equal((await kill('p1')).winner, null, 'first assassin out');
    assert.equal((await kill('p2')).winner, null, 'second assassin out — leader still alive');
    assert.equal((await kill('p0')).winner, 'traitor', 'leader out, traitor alone');

    const g = await h.getGame(game.gameId);
    assert.equal(g.state, 'finished');
    assert.equal(g.winning_team, 'traitor');
  });

  it('rejects further adjustments after the game has finished', async () => {
    const game = await startedTreacheryGame(SEATS_4P);
    await game.users[1].call('adjustLife', {
      gameId: game.gameId,
      playerId: 'p0',
      amount: -40,
    });
    await h.expectHttpsError(
      game.users[1].call('adjustLife', { gameId: game.gameId, playerId: 'p3', amount: -5 }),
      'failed-precondition'
    );
  });
});

describe('adjustLife — non-treachery modes must not auto-finish', () => {
  // SKIP: currently broken — see finding #B. Un-skip when functions/index.js is fixed.
  //
  // checkWinConditions() (index.js ~143) has no game-mode guard. In
  // "none"/"planechase" games every player's `role` is null, so the
  // "!leaderAlive && !assassinAlive && !traitorAlive" branch fires on the very
  // first elimination and hands the game to the (non-existent) assassins.
  // A Life Tracker game therefore ends as soon as one player hits 0.
  for (const mode of ['none', 'planechase']) {
    it(
      `a "${mode}" game keeps running when a player drops to 0 life`,
      async () => {
        const users = await h.getUsers(4);
        const game = await h.seedGame({ users, gameMode: mode, startingLife: 40 });
        await game.host.call('startGame', { gameId: game.gameId });

        const res = await game.users[1].call('adjustLife', {
          gameId: game.gameId,
          playerId: 'p1',
          amount: -40,
        });

        assert.equal(res.eliminated, true, 'the player is still eliminated');
        assert.equal(
          res.winner,
          null,
          `a "${mode}" game has no automatic win condition`
        );

        const g = await h.getGame(game.gameId);
        assert.equal(
          g.state,
          'in_progress',
          `a "${mode}" game must not finish itself after one elimination`
        );
        assert.equal(
          g.winning_team,
          undefined,
          `a "${mode}" game must never set winning_team`
        );
      }
    );
  }

  // SKIP: currently broken — see finding #B. Un-skip when functions/index.js is fixed.
  //
  // The same bug means the host can never legitimately call endGame: the game
  // has already flipped to "finished" behind their back.
  it(
    'the host can still end a Life Tracker game explicitly after an elimination',
    async () => {
      const users = await h.getUsers(4);
      const game = await h.seedGame({ users, gameMode: 'none', startingLife: 40 });
      await game.host.call('startGame', { gameId: game.gameId });

      await game.users[1].call('adjustLife', {
        gameId: game.gameId,
        playerId: 'p1',
        amount: -40,
      });

      const res = await game.host.call('endGame', {
        gameId: game.gameId,
        winnerUserIds: [users[0].uid],
      });
      assert.deepEqual(res, { action: 'ended' });

      const g = await h.getGame(game.gameId);
      assert.equal(g.state, 'finished');
      assert.deepEqual(g.winner_user_ids, [users[0].uid]);
      assert.equal(g.winning_team, undefined);
    }
  );
});
