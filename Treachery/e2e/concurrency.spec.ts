import { test, expect } from '@playwright/test';
import {
  LIFE_DEBOUNCE_MS,
  Role,
  damage,
  expectServerLife,
  fetchPlayerDocs,
  playersWithRole,
  setupSeededGame,
} from './helpers';

/**
 * Concurrent life adjustments from two different players.
 *
 * Real tables do this constantly — two people tap the same victim at once. The
 * board is optimistic and debounces taps for ~500ms before flushing a single
 * `adjustLife` call, and the snapshot listener clears a client's *pending*
 * delta as soon as the server total changes for that player, so a tap made
 * while someone else's flush is in flight is thrown away before it is ever
 * sent. The server never hears about it and the total is silently short.
 *
 * These tests assert the arithmetic on the server, not on screen: the
 * optimistic UI can show the right number while the durable total is wrong.
 */

const LAYOUT: Role[] = ['leader', 'assassin', 'assassin', 'traitor'];
const STARTING_LIFE = 20;

test.describe('Two players adjusting the same target', () => {
  test('sequential adjustments from different players both land', async ({ browser }) => {
    // Baseline: the same two taps, spaced far enough apart that neither
    // client has a pending delta when the other's update arrives.
    const { players, gameId } = await setupSeededGame(browser, LAYOUT, {
      startingLife: STARTING_LIFE,
    });
    const [actorA, actorB] = playersWithRole(players, 'assassin');
    const target = players.find((p) => p.role === 'traitor')!;

    await damage(actorA.page, target.name, 1);
    await expectServerLife(actorA.page, gameId, target.userId, STARTING_LIFE - 1);

    await damage(actorB.page, target.name, 1);
    await expectServerLife(actorB.page, gameId, target.userId, STARTING_LIFE - 2);
  });

  // FIXME: currently broken — see finding #4. Un-fixme when the bug is fixed.
  // useGameBoard's snapshot listener zeroes `lifeDeltasRef.current[playerId]`
  // whenever the server total for that player changes, including while this
  // client still has an un-flushed tap queued. flushLifeDelta then sees 0 and
  // returns without calling adjustLife, so the second player's damage is lost.
  // The pending delta should be tracked per in-flight request instead of being
  // cleared by any incoming snapshot.
  test.fixme('near-simultaneous adjustments from different players both land', async ({
    browser,
  }) => {
    const { players, gameId } = await setupSeededGame(browser, LAYOUT, {
      startingLife: STARTING_LIFE,
    });
    const [actorA, actorB] = playersWithRole(players, 'assassin');
    const target = players.find((p) => p.role === 'traitor')!;

    // A taps, then B taps inside A's debounce window. A's flush lands first
    // and the resulting snapshot wipes B's queued tap.
    await damage(actorA.page, target.name, 1);
    await actorB.page.waitForTimeout(LIFE_DEBOUNCE_MS * 0.6);
    await damage(actorB.page, target.name, 1);

    await expectServerLife(actorA.page, gameId, target.userId, STARTING_LIFE - 2, 15_000);
  });

  // FIXME: currently broken — see finding #4. Un-fixme when the bug is fixed.
  // Same root cause, with multi-tap bursts: whichever client's flush lands
  // second loses its entire accumulated delta, not just one point.
  test.fixme('overlapping multi-tap bursts from different players both land', async ({
    browser,
  }) => {
    const { players, gameId } = await setupSeededGame(browser, LAYOUT, {
      startingLife: STARTING_LIFE,
    });
    const [actorA, actorB] = playersWithRole(players, 'assassin');
    const target = players.find((p) => p.role === 'traitor')!;

    await damage(actorA.page, target.name, 3);
    await actorB.page.waitForTimeout(LIFE_DEBOUNCE_MS * 0.6);
    await damage(actorB.page, target.name, 4);

    await expectServerLife(actorA.page, gameId, target.userId, STARTING_LIFE - 7, 15_000);

    // And the target is not eliminated by a phantom overshoot either.
    const docs = await fetchPlayerDocs(actorA.page, gameId);
    expect(docs.find((d) => d.user_id === target.userId)?.is_eliminated).toBe(false);
  });
});
