import { test, expect } from '@playwright/test';
import {
  setupSeededGame,
  playerWithRole,
  playersWithRole,
  forfeit,
  expectWinner,
  ROLE_DISTRIBUTION,
  PlayerHandle,
  Role,
} from './helpers';

/**
 * 5 player counts × 3 win conditions = 15 tests.
 *
 * Strategy: each player count gets a deterministic role layout (host = leader
 * by convention, then guardians, assassins, traitors in order). Tests use the
 * emulator-only testSeed to assign roles + cards directly, then drive each
 * win condition by forfeiting players one at a time. Forfeit is a single
 * cloud-function call (vs. ~40 -1 clicks to damage someone to 0), so the
 * matrix runs in a few minutes rather than 30+.
 *
 * Win condition derivations (see checkWinConditions in functions/index.js):
 *   - "Leader" wins   when the leader is alive AND no assassins/traitors are alive.
 *   - "Assassin" wins when the leader is eliminated AND ≥1 assassin is alive.
 *   - "Traitor" wins  when exactly one player is alive AND they're a traitor.
 */

const PLAYER_COUNTS = [4, 5, 6, 7, 8] as const;

function buildLayout(count: number): Role[] {
  const dist = ROLE_DISTRIBUTION[count];
  const layout: Role[] = [];
  for (let i = 0; i < dist.leader; i++) layout.push('leader');
  for (let i = 0; i < dist.guardian; i++) layout.push('guardian');
  for (let i = 0; i < dist.assassin; i++) layout.push('assassin');
  for (let i = 0; i < dist.traitor; i++) layout.push('traitor');
  return layout;
}

async function forfeitInOrder(targets: PlayerHandle[]) {
  for (const player of targets) {
    await forfeit(player.page);
    // Page navigates to /game-over/ after forfeit; wait for it before the next
    // forfeit to keep ordering deterministic.
    await expect(player.page).toHaveURL(/\/game-over\//, { timeout: 15_000 });
  }
}

for (const count of PLAYER_COUNTS) {
  test.describe(`${count}-player game`, () => {
    // Each describe block is its own isolated game; the 3 tests inside it
    // share nothing. Playwright runs them sequentially (workers: 1).

    test('leader wins after eliminating all assassins and traitors', async ({ browser }) => {
      const { players } = await setupSeededGame(browser, buildLayout(count));
      const assassins = playersWithRole(players, 'assassin');
      const traitors = playersWithRole(players, 'traitor');
      // Leader (and any guardians) survive.
      await forfeitInOrder([...assassins, ...traitors]);
      await expectWinner(
        players.map((p) => p.page),
        'Leader',
      );
    });

    test('assassins win when the leader is eliminated', async ({ browser }) => {
      const { players } = await setupSeededGame(browser, buildLayout(count));
      const leader = playerWithRole(players, 'leader');
      // ≥1 assassin alive at this point, so the assassin team wins immediately.
      await forfeitInOrder([leader]);
      await expectWinner(
        players.map((p) => p.page),
        'Assassin',
      );
    });

    test('traitor wins as the last player standing', async ({ browser }) => {
      const { players } = await setupSeededGame(browser, buildLayout(count));
      const assassins = playersWithRole(players, 'assassin');
      const guardians = playersWithRole(players, 'guardian');
      const leader = playerWithRole(players, 'leader');
      const traitors = playersWithRole(players, 'traitor');
      // Order matters: assassins → guardians → leader → all-but-one traitor.
      // We can't kill the leader before all assassins are dead (assassin win
      // would fire), and we can't leave traitors alive at the end without
      // being one of them (traitor solo win requires alive.length === 1).
      const order = [
        ...assassins,
        ...guardians,
        leader,
        ...traitors.slice(0, -1),
      ];
      await forfeitInOrder(order);
      await expectWinner(
        players.map((p) => p.page),
        'Traitor',
      );
    });
  });
}
