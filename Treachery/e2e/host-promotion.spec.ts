import { test, expect } from '@playwright/test';
import { fetchGameDoc, fetchPlayerDocs, setupLobby } from './helpers';

/**
 * Host promotion: what happens to a lobby when the host walks away.
 *
 * `leaveGame` promotes the next player by order_id rather than disbanding
 * (functions/index.js → action: "promoted"), so the remaining players should
 * be able to carry on and start the game. The server half works; the lobby
 * screen's half does not.
 */

test.describe('Host leaves a lobby with players still in it', () => {
  test('the server promotes the next player and the lobby shows the new host', async ({
    browser,
  }) => {
    const { pages, userIds, gameId } = await setupLobby(browser, 3);
    const [hostPage, secondPage, thirdPage] = pages;

    expect((await fetchGameDoc(hostPage, gameId))?.host_id).toBe(userIds[0]);

    // Host leaves, accepting the in-app confirmation.
    await hostPage.getByRole('button', { name: 'Leave game' }).click();
    await hostPage.getByRole('button', { name: 'Confirm leave' }).click();

    // The game survives, and host_id moves to the next seat.
    await expect
      .poll(async () => (await fetchGameDoc(secondPage, gameId))?.host_id, { timeout: 15_000 })
      .toBe(userIds[1]);
    expect((await fetchGameDoc(secondPage, gameId))?.state).toBe('waiting');

    // The old host's player doc is gone; the other two remain.
    const docs = await fetchPlayerDocs(secondPage, gameId);
    expect(docs.map((d) => d.user_id).sort()).toEqual([userIds[1], userIds[2]].sort());

    // Both remaining lobbies re-render with the Host badge on the new host.
    // (The badge is derived from game.host_id, so this part already works.)
    // `exact` matters: getByText is case-insensitive substring matching by
    // default, which also picks up "Waiting for host to start the game...".
    for (const page of [secondPage, thirdPage]) {
      await expect(page.getByText('Players (2)')).toBeVisible();
      await expect(page.getByText('Host', { exact: true })).toHaveCount(1);
    }
  });

  // FIXME: currently broken — see finding #3. Un-fixme when the bug is fixed.
  // The lobby screen freezes `isHost` from the `isHost` navigation param it was
  // opened with (`const isHost = isHostParam === 'true'`), so a player promoted
  // by the server still renders the guest view: no Start Game button, and
  // useLobby.startGame bails out on `if (!isHost) return`. The promoted host
  // has to leave and rejoin to unstick the lobby. isHost should be derived from
  // game.host_id === currentUserId.
  test('the promoted host can start the game', async ({ browser }) => {
    const { pages, userIds, gameId } = await setupLobby(browser, 3);
    const [hostPage, secondPage, thirdPage] = pages;

    await hostPage.getByRole('button', { name: 'Leave game' }).click();
    await hostPage.getByRole('button', { name: 'Confirm leave' }).click();

    await expect
      .poll(async () => (await fetchGameDoc(secondPage, gameId))?.host_id, { timeout: 15_000 })
      .toBe(userIds[1]);

    // The promoted player now owns the lobby: settings and Start Game.
    await expect(secondPage.getByText('GAME SETTINGS')).toBeVisible();
    const start = secondPage.getByRole('button', { name: 'Start game' });
    await expect(start).toBeEnabled({ timeout: 15_000 });
    await start.click();

    await Promise.all(
      [secondPage, thirdPage].map((p) => expect(p).toHaveURL(/\/game\//, { timeout: 20_000 })),
    );
    expect((await fetchGameDoc(secondPage, gameId))?.state).toBe('in_progress');
  });
});
