'use strict';

/**
 * INTEGRATION: exports.unveilPlayer (functions/index.js)
 */

const { describe, it, after } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

after(async () => {
  await h.shutdown();
});

const SEATS_4P = [
  { role: 'leader', card: 'leader_01' },
  { role: 'assassin', card: 'assassin_01' },
  { role: 'assassin', card: 'assassin_02' },
  { role: 'traitor', card: 'traitor_01' },
];

function startedGame(users) {
  return h.seedStartedGame({ users, seats: SEATS_4P });
}

describe('unveilPlayer', () => {
  it('unveils the caller', async () => {
    const users = await h.getUsers(4);
    const game = await startedGame(users);

    const res = await users[1].call('unveilPlayer', { gameId: game.gameId });
    assert.deepEqual(res, { success: true });

    const p = await h.getPlayer(game.gameId, 'p1');
    assert.equal(p.is_unveiled, true);
    assert.equal(p.identity_card_id, 'assassin_01', 'unveiling does not change the card');
    assert.equal(p.role, 'assassin', 'unveiling does not change the role');

    const others = await h.getPlayers(game.gameId);
    assert.deepEqual(
      others.filter((o) => o.id !== 'p1').map((o) => o.is_unveiled),
      [false, false, false],
      'unveiling one player must not unveil anyone else'
    );
  });

  it('rejects a double unveil', async () => {
    const users = await h.getUsers(4);
    const game = await startedGame(users);
    await users[3].call('unveilPlayer', { gameId: game.gameId });
    await h.expectHttpsError(
      users[3].call('unveilPlayer', { gameId: game.gameId }),
      'failed-precondition'
    );
  });

  it('rejects the Leader, whose identity is always public', async () => {
    const users = await h.getUsers(4);
    const game = await startedGame(users);
    await h.expectHttpsError(
      users[0].call('unveilPlayer', { gameId: game.gameId }),
      'failed-precondition'
    );
    const p = await h.getPlayer(game.gameId, 'p0');
    assert.equal(p.is_unveiled, false);
  });

  it('rejects an eliminated player', async () => {
    const users = await h.getUsers(4);
    const game = await startedGame(users);
    // Eliminate without the elimination's automatic unveil, so the test hits
    // the is_eliminated gate rather than the is_unveiled one.
    await h.patchPlayer(game.gameId, 'p2', { is_eliminated: true, life_total: 0 });

    await h.expectHttpsError(
      users[2].call('unveilPlayer', { gameId: game.gameId }),
      'failed-precondition'
    );
    const p = await h.getPlayer(game.gameId, 'p2');
    assert.equal(p.is_unveiled, false);
  });

  it('rejects a caller who is not in the game', async () => {
    const users = await h.getUsers(5);
    const game = await startedGame(users.slice(0, 4));
    await h.expectHttpsError(
      users[4].call('unveilPlayer', { gameId: game.gameId }),
      'not-found'
    );
  });

  it('rejects unveiling before the game starts', async () => {
    const users = await h.getUsers(4);
    const game = await h.seedGame({ users });
    await h.expectHttpsError(
      users[1].call('unveilPlayer', { gameId: game.gameId }),
      'failed-precondition'
    );
  });

  it('rejects an unknown gameId', async () => {
    const [user] = await h.getUsers(1);
    await h.expectHttpsError(
      user.call('unveilPlayer', { gameId: 'nope' }),
      'not-found'
    );
  });

  it('rejects an unauthenticated caller', async () => {
    const users = await h.getUsers(4);
    const game = await startedGame(users);
    await h.expectHttpsError(
      h.unauthenticatedCaller()('unveilPlayer', { gameId: game.gameId }),
      'unauthenticated'
    );
  });

  it('clears a face-down flag left by a Puppet Master swap', async () => {
    const users = await h.getUsers(4);
    const game = await h.seedStartedGame({
      users,
      seats: [
        { role: 'leader', card: 'leader_01' },
        { role: 'assassin', card: 'assassin_01' },
        { role: 'assassin', card: 'assassin_02' },
        { role: 'traitor', card: 'traitor_09' },
      ],
    });
    await users[3].call('unveilPlayer', { gameId: game.gameId });
    await users[3].call('resolvePuppetMaster', {
      gameId: game.gameId,
      redistributions: { p1: 'assassin_02', p2: 'assassin_01' },
    });

    let p = await h.getPlayer(game.gameId, 'p1');
    assert.equal(p.is_face_down, true, 'the swapped-in card starts face-down');

    const res = await users[1].call('unveilPlayer', { gameId: game.gameId });
    assert.deepEqual(res, { success: true });

    p = await h.getPlayer(game.gameId, 'p1');
    assert.equal(p.is_unveiled, true);
    assert.equal(p.is_face_down, false, 'unveiling must reveal the CURRENT card');
    assert.equal(p.identity_card_id, 'assassin_02');
  });
});
