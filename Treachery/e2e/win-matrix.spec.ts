import { test, expect } from '@playwright/test';
import {
  setupSeededGame,
  playerWithRole,
  playersWithRole,
  forfeit,
  expectWinner,
  fetchPlayerDocs,
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

/**
 * Forfeit each target in order. Mid-game forfeits stay on the board (no
 * spoiler trip to /game-over); we wait for the server elimination instead so
 * the next forfeit is sequenced correctly.
 */
async function forfeitInOrder(
  targets: PlayerHandle[],
  reader: PlayerHandle,
  gameId: string,
) {
  for (const player of targets) {
    await forfeit(player.page);
    await expect(async () => {
      const docs = await fetchPlayerDocs(reader.page, gameId);
      const doc = docs.find((d) => d.user_id === player.userId);
      expect(doc?.is_eliminated).toBe(true);
    }).toPass({ timeout: 15_000 });
  }
}

for (const count of PLAYER_COUNTS) {
  test.describe(`${count}-player game`, () => {
    // Each describe block is its own isolated game; the 3 tests inside it
    // share nothing. Playwright runs them sequentially (workers: 1).

    test('leader wins after eliminating all assassins and traitors', async ({ browser }) => {
      const { players, gameId } = await setupSeededGame(browser, buildLayout(count));
      const leader = playerWithRole(players, 'leader');
      const assassins = playersWithRole(players, 'assassin');
      const traitors = playersWithRole(players, 'traitor');
      // Leader (and any guardians) survive.
      await forfeitInOrder([...assassins, ...traitors], leader, gameId);
      await expectWinner(
        players.map((p) => p.page),
        'Leader',
      );
    });

    test('assassins win when the leader is eliminated', async ({ browser }) => {
      const { players, gameId } = await setupSeededGame(browser, buildLayout(count));
      const leader = playerWithRole(players, 'leader');
      // ≥1 assassin alive at this point, so the assassin team wins immediately.
      // Reader can be the forfeiter; settle still reads Firestore offline after nav.
      await forfeitInOrder([leader], leader, gameId);
      await expectWinner(
        players.map((p) => p.page),
        'Assassin',
      );
    });

    test('traitor wins as the last player standing', async ({ browser }) => {
      const { players, gameId } = await setupSeededGame(browser, buildLayout(count));
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
      // Survivor traitor stays mounted until the final win; use them as reader.
      await forfeitInOrder(order, traitors[traitors.length - 1], gameId);
      await expectWinner(
        players.map((p) => p.page),
        'Traitor',
      );
    });
  });
}
