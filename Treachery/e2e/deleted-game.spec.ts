import { test, expect, Page } from '@playwright/test';
import { fetchGameDoc, hostCreateGame, signInAsGuest } from './helpers';

/**
 * A lobby or game that no longer exists.
 *
 * The hourly cleanupStaleGames sweep deletes lobbies and games left idle for
 * 24 hours, so a bookmarked or restored /lobby/<id> or /game/<id> tab, or a
 * /game-over/<id> tab opened before its game finished, can point at a game
 * that is gone. The board and lobby used to notice only a game deleted while
 * open, and the results screen not even that: one already missing on the
 * first snapshot left them on a spinner for good. Here the game goes the
 * ordinary way a lobby does: its only player, the host, leaves, and
 * leaveGame deletes it.
 */

async function leaveAsOnlyPlayer(page: Page) {
  await page.getByRole('button', { name: 'Leave game' }).click();
  await page.getByRole('button', { name: 'Confirm leave' }).click();
}

test.describe('A game that no longer exists', () => {
  test('a lobby deleted while it is open says it has closed', async ({ page }) => {
    await signInAsGuest(page);
    const { gameId } = await hostCreateGame(page);

    // A second tab of the same account, with the lobby open.
    const watcher = await page.context().newPage();
    await watcher.goto(`/lobby/${gameId}`);
    await expect(watcher.getByText('Game Code', { exact: true })).toBeVisible({ timeout: 20_000 });

    await leaveAsOnlyPlayer(page);

    await expect(watcher.getByText('Game Disbanded', { exact: true })).toBeVisible({
      timeout: 15_000,
    });
    await expect(watcher.getByText('This lobby has closed.')).toBeVisible();
  });

  test('opening its board, lobby or results link says it is gone instead of loading forever', async ({
    page,
  }) => {
    await signInAsGuest(page);
    const { gameId } = await hostCreateGame(page);
    await leaveAsOnlyPlayer(page);
    await expect(page.getByRole('button', { name: 'Create game' })).toBeVisible();
    await expect.poll(() => fetchGameDoc(page, gameId)).toBeNull();

    // Fresh page loads, as from a bookmark or a restored tab: the first
    // snapshot already says the game doesn't exist.
    await page.goto(`/game/${gameId}`);
    await expect(page.getByText('Game Unavailable', { exact: true })).toBeVisible({
      timeout: 20_000,
    });
    await page.getByRole('button', { name: 'Return to home' }).click();
    await expect(page.getByRole('button', { name: 'Create game' })).toBeVisible();

    await page.goto(`/lobby/${gameId}`);
    await expect(page.getByText('Game Disbanded', { exact: true })).toBeVisible({
      timeout: 20_000,
    });
    await expect(page.getByText('This lobby has closed.')).toBeVisible();
    await page.getByRole('button', { name: 'Return home' }).click();
    await expect(page.getByRole('button', { name: 'Create game' })).toBeVisible();

    await page.goto(`/game-over/${gameId}`);
    await expect(page.getByText('Game Unavailable', { exact: true })).toBeVisible({
      timeout: 20_000,
    });
    await page.getByRole('button', { name: 'Return to home' }).click();
    await expect(page.getByRole('button', { name: 'Create game' })).toBeVisible();
  });
});
