import { test, expect } from '@playwright/test';
import { fetchPlayerDocs, setupSeededGame } from './helpers';

/**
 * Guest naming and in-game rename.
 *
 * Guests used to default to the literal name "Guest", so a table of four
 * guests was indistinguishable. Onboarding now prefills a random Magic
 * character name, and players can rename themselves from their own row on
 * the game board (pencil icon → inline input).
 */

test('a new guest is offered a random name instead of "Guest"', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'Play as Guest' }).click();

  const input = page.getByLabel('Display name');
  await expect(input).toBeVisible();
  const suggested = await input.inputValue();

  // A concrete name from the pool — never the old default, never blank.
  expect(suggested).not.toBe('');
  expect(suggested).not.toBe('Guest');

  // Skip must KEEP the suggestion (otherwise the user doc stays "Guest" and
  // the four-guests-named-Guest problem returns through the skip path).
  await page.getByRole('button', { name: 'Skip' }).click();
  await page.getByRole('button', { name: "Let's Play" }).click();
  await page.getByRole('button', { name: 'Create game' }).click();
  await page.getByRole('button', { name: 'Create game' }).click();
  await expect(page).toHaveURL(/\/lobby\//);
  await expect(page.getByText(suggested).first()).toBeVisible();
});

test('a player can rename themselves mid-game and the table sees it', async ({ browser }) => {
  const { players, gameId } = await setupSeededGame(browser, [
    'leader',
    'assassin',
    'assassin',
    'traitor',
  ]);
  const renamer = players[1];
  const observer = players[0];

  await renamer.page.getByRole('button', { name: 'Edit your name' }).click();
  const input = renamer.page.getByLabel('Your name');
  await input.fill('Krenko');
  await input.press('Enter');

  // The renamer's own row updates...
  await expect(renamer.page.getByText('Krenko')).toBeVisible();
  // ...another player's board sees it via the snapshot listener...
  await expect(observer.page.getByText('Krenko')).toBeVisible({ timeout: 10_000 });

  // ...and both documents record it: the player doc (this game) and the user
  // doc (future games).
  await expect
    .poll(async () => {
      const docs = await fetchPlayerDocs(observer.page, gameId);
      return docs.find((d) => d.user_id === renamer.userId)?.display_name;
    })
    .toBe('Krenko');
});
