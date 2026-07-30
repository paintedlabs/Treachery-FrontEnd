import { test, expect } from '@playwright/test';
import {
  signInAsGuest,
  hostCreateGame,
  guestJoinGame,
  fetchGameDoc,
  fetchPlayerDocs,
} from './helpers';

/**
 * Max traitor rarity cap — exercises the real (unseeded) startGame path.
 *
 * The host caps the traitor pool at Uncommon via the lobby settings row
 * (updateGameSettings cloud function), then starts a 4-player game. The
 * assigned traitor must be one of the four uncommon traitor identities.
 *
 * Kept in sync with functions/identityCards.json by the "Traitor Rarity Cap"
 * suite in functions/test/game-logic.test.js, which derives these from data.
 */
const UNCOMMON_TRAITOR_IDS = [
  'traitor_01', // The Banisher
  'traitor_04', // The Gatekeeper
  'traitor_05', // The Grenadier
  'traitor_08', // The Oneiromancer
];

test('host caps traitor rarity at Uncommon and the assigned traitor respects it', async ({
  browser,
}) => {
  const contexts = await Promise.all(
    Array.from({ length: 4 }, () => browser.newContext()),
  );
  const [host, guest1, guest2, guest3] = await Promise.all(
    contexts.map((ctx) => ctx.newPage()),
  );

  await Promise.all([host, guest1, guest2, guest3].map((p) => signInAsGuest(p)));

  const { gameId, code } = await hostCreateGame(host);

  // The create screen defaults the cap to Special (all traitors) and writes
  // it onto the game doc for treachery-mode games.
  await expect
    .poll(async () => (await fetchGameDoc(host, gameId))?.max_traitor_rarity)
    .toBe('special');

  // Host tightens the cap to Uncommon from the lobby settings.
  await host
    .getByRole('button', { name: 'Set max traitor rarity to Uncommon' })
    .click();
  await expect
    .poll(async () => (await fetchGameDoc(host, gameId))?.max_traitor_rarity)
    .toBe('uncommon');

  await Promise.all([guest1, guest2, guest3].map((p) => guestJoinGame(p, code)));
  await expect(host.getByText('Players (4)')).toBeVisible();

  await expect(host.getByRole('button', { name: 'Start game' })).toBeEnabled();
  await host.getByRole('button', { name: 'Start game' }).click();

  await Promise.all(
    [host, guest1, guest2, guest3].map((p) =>
      expect(p).toHaveURL(/\/game\//, { timeout: 20_000 }),
    ),
  );

  // A 4-player game seats exactly one traitor; their card must be uncommon.
  const players = await fetchPlayerDocs(host, gameId);
  const traitors = players.filter((p) => p.role === 'traitor');
  expect(traitors).toHaveLength(1);
  expect(UNCOMMON_TRAITOR_IDS).toContain(traitors[0].identity_card_id);
});
