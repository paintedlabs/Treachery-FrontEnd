import { test, expect, Page } from '@playwright/test';

/**
 * E2E happy path: host creates a game, three guests join, host starts.
 *
 * Why this test exists: the recent ready-up P0 had a client-side gate
 * (the host's Start button stayed disabled) that no server-side test
 * could catch. This walks the actual UI.
 *
 * Player count: production builds enforce a 4-player minimum for
 * treachery mode (see MINIMUM_PLAYER_COUNT in src/constants/roles.ts),
 * so this test creates four contexts.
 */

async function signInAsGuest(page: Page) {
  await page.goto('/');
  await page.getByRole('button', { name: 'Play as Guest' }).click();
  // First-run onboarding: display name (default "Guest" works) -> welcome -> home.
  await page.getByRole('button', { name: 'Continue' }).click();
  await page.getByRole('button', { name: "Let's Play" }).click();
  await expect(page.getByRole('button', { name: 'Create game' })).toBeVisible({ timeout: 20_000 });
}

async function joinGameWithCode(page: Page, code: string) {
  await page.getByRole('button', { name: 'Join game' }).click();
  await expect(page).toHaveURL(/\/join-game/);
  await page.getByLabel('Game code').fill(code);
  await page.getByRole('button', { name: 'Join game' }).click();
  await expect(page).toHaveURL(/\/lobby\//);
}

test('host creates, three guests join, host starts the game', async ({ browser }) => {
  const contexts = await Promise.all(
    Array.from({ length: 4 }, () => browser.newContext()),
  );
  const [host, guest1, guest2, guest3] = await Promise.all(
    contexts.map((ctx) => ctx.newPage()),
  );

  // Sign all four in in parallel.
  await Promise.all([host, guest1, guest2, guest3].map(signInAsGuest));

  // Host: home -> create-game -> lobby
  await host.getByRole('button', { name: 'Create game' }).click();
  await expect(host).toHaveURL(/\/create-game/);
  await host.getByRole('button', { name: 'Create game' }).click();
  await expect(host).toHaveURL(/\/lobby\//);

  // Read the 4-character game code displayed in the lobby.
  const code = (
    await host.getByText(/^[A-Z0-9]{4}$/).first().textContent()
  )?.trim();
  expect(code).toMatch(/^[A-Z0-9]{4}$/);

  // Start button is disabled while the host is the only player.
  await expect(host.getByRole('button', { name: 'Start game' })).toBeDisabled();

  // Three guests join with the code.
  await Promise.all([guest1, guest2, guest3].map((p) => joinGameWithCode(p, code!)));

  // Host's lobby should now show 4 players.
  await expect(host.getByText('Players (4)')).toBeVisible();

  // Host starts. All four clients should navigate to the game board.
  await expect(host.getByRole('button', { name: 'Start game' })).toBeEnabled();
  await host.getByRole('button', { name: 'Start game' }).click();

  await Promise.all(
    [host, guest1, guest2, guest3].map((p) =>
      expect(p).toHaveURL(/\/game\//, { timeout: 20_000 }),
    ),
  );
});
