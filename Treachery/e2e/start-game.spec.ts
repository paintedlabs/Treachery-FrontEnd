import { test, expect } from '@playwright/test';
import {
  signInAsGuest,
  hostCreateGame,
  guestJoinGame,
} from './helpers';

/**
 * E2E happy path that goes through the **real** Start button (no testSeed).
 *
 * This spec deliberately exercises the random role-assignment path of
 * startGame, which the seeded specs in win-matrix.spec.ts and abilities.spec.ts
 * intentionally bypass. Production builds enforce a 4-player minimum for
 * treachery mode (MINIMUM_PLAYER_COUNT in src/constants/roles.ts), so this
 * test creates four contexts and uses the lobby's Start button.
 */

test('host creates, three guests join, host starts the game', async ({ browser }) => {
  const contexts = await Promise.all(
    Array.from({ length: 4 }, () => browser.newContext()),
  );
  const [host, guest1, guest2, guest3] = await Promise.all(
    contexts.map((ctx) => ctx.newPage()),
  );

  await Promise.all([host, guest1, guest2, guest3].map(signInAsGuest));

  const { code } = await hostCreateGame(host);

  // (We don't assert "Start disabled with 1 player" here because MINIMUM_PLAYER_COUNT
  // is gated on EXPO_PUBLIC_ENVIRONMENT — emulator builds use 1, production uses 4.
  // The win-matrix specs cover the 4-player-minimum end-state via testSeed instead.)

  await Promise.all([guest1, guest2, guest3].map((p) => guestJoinGame(p, code)));

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
