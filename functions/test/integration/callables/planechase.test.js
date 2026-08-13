'use strict';

/**
 * INTEGRATION: planechase callables (rollPlanarDie, resolvePhenomenon, selectPlane)
 */

const { describe, it, after } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

const INTERPLANAR_TUNNEL_ID = '7812174b-2dc1-43e8-b98f-639905e20ab7';
const ACADEMY_PLANE_ID = '15b979de-c8ee-4664-9ca7-6c4eb3346967';

after(async () => {
  await h.shutdown();
});

async function startedPlanechase(userCount = 2, extra = {}) {
  const users = await h.getUsers(userCount);
  const seated = users.slice(0, 2);
  const game = await h.seedGame({ users: seated, gameMode: 'planechase', ...extra });
  await game.host.call('startGame', { gameId: game.gameId });
  return { game, users, outsider: users[2] };
}

describe('planechase callables — authz', () => {
  it('rejects rollPlanarDie from a non-seated user', async () => {
    const { game, outsider } = await startedPlanechase(3);
    await h.expectHttpsError(
      outsider.call('rollPlanarDie', { gameId: game.gameId }),
      'permission-denied'
    );
  });

  it('rejects rollPlanarDie in a treachery-only game', async () => {
    const users = await h.getUsers(4);
    const game = await h.seedGame({ users, gameMode: 'treachery' });
    await game.host.call('startGame', { gameId: game.gameId });
    await h.expectHttpsError(
      game.host.call('rollPlanarDie', { gameId: game.gameId }),
      'failed-precondition'
    );
  });

  it('rejects resolvePhenomenon from a non-seated user', async () => {
    const { game, outsider } = await startedPlanechase(3);
    await h.patchGame(game.gameId, {
      'planechase.current_plane_id': INTERPLANAR_TUNNEL_ID,
    });
    await h.expectHttpsError(
      outsider.call('resolvePhenomenon', { gameId: game.gameId }),
      'permission-denied'
    );
  });
});

describe('selectPlane', () => {
  it('rejects cherry-picking a plane without an Interplanar Tunnel offer', async () => {
    const { game } = await startedPlanechase();
    await h.expectHttpsError(
      game.host.call('selectPlane', { gameId: game.gameId, planeId: ACADEMY_PLANE_ID }),
      'failed-precondition'
    );
  });

  it('rejects a plane that was not among the persisted tunnel options', async () => {
    const { game } = await startedPlanechase();
    await h.patchGame(game.gameId, {
      'planechase.current_plane_id': INTERPLANAR_TUNNEL_ID,
      'planechase.pending_plane_options': ['38f84e55-049c-441e-b4e2-1e207ab5dbe5'],
    });
    await h.expectHttpsError(
      game.host.call('selectPlane', { gameId: game.gameId, planeId: ACADEMY_PLANE_ID }),
      'invalid-argument'
    );
  });

  it('accepts a plane from the persisted tunnel options', async () => {
    const { game } = await startedPlanechase();
    await h.patchGame(game.gameId, {
      'planechase.current_plane_id': INTERPLANAR_TUNNEL_ID,
      'planechase.pending_plane_options': [ACADEMY_PLANE_ID],
    });
    const res = await game.host.call('selectPlane', {
      gameId: game.gameId,
      planeId: ACADEMY_PLANE_ID,
    });
    assert.deepEqual(res, { newPlaneId: ACADEMY_PLANE_ID });
    const g = await h.getGame(game.gameId);
    assert.equal(g.planechase.current_plane_id, ACADEMY_PLANE_ID);
    assert.equal(g.planechase.pending_plane_options, undefined);
  });
});
