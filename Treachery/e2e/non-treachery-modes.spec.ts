import { test, expect } from '@playwright/test';
import {
  GameMode,
  damage,
  expectServerLife,
  fetchGameDoc,
  fetchPlayerDocs,
  setupNonTreacheryGame,
} from './helpers';

/**
 * Non-treachery game modes: Life Tracker ('none') and Planechase.
 *
 * These modes have no roles, no identity cards, and no automatic win
 * conditions — the host ends the game explicitly with End Game. Dropping a
 * player to 0 life should therefore knock that one player out and leave
 * everyone else playing.
 *
 * The whole suite was treachery-only before this file, so every one of these
 * paths (startGame's non-treachery branch, the roleless game board, the
 * non-treachery game-over summary) was completely uncovered.
 *
 * A low starting life keeps this quick: eliminating a player costs one `-1`
 * click per point of life.
 */

const STARTING_LIFE = 20;

const MODES: { mode: Exclude<GameMode, 'treachery' | 'treachery_planechase'>; label: string }[] = [
  { mode: 'none', label: 'Life Tracker' },
  { mode: 'planechase', label: 'Planechase' },
];

for (const { mode, label } of MODES) {
  test.describe(`${label} mode`, () => {
    test('starts with no roles or identity cards assigned', async ({ browser }) => {
      const { gameId, players } = await setupNonTreacheryGame(browser, 4, mode, {
        startingLife: STARTING_LIFE,
      });

      const game = await fetchGameDoc(players[0].page, gameId);
      expect(game?.game_mode).toBe(mode);
      expect(game?.state).toBe('in_progress');

      const docs = await fetchPlayerDocs(players[0].page, gameId);
      expect(docs).toHaveLength(4);
      for (const doc of docs) {
        expect(doc.role).toBeNull();
        expect(doc.identity_card_id).toBeNull();
        expect(doc.life_total).toBe(STARTING_LIFE);
      }

      // No treachery affordances on the board: nothing to unveil or forfeit.
      await expect(players[1].page.getByRole('button', { name: 'Unveil identity' })).toHaveCount(0);
      await expect(players[1].page.getByRole('button', { name: 'Forfeit' })).toHaveCount(0);
    });

    // FIXME: currently broken — see finding #1. Un-fixme when the bug is fixed.
    // adjustLife runs checkWinConditions for every mode. With no roles at all,
    // checkWinConditions falls through to `!leaderAlive && !assassinAlive &&
    // !traitorAlive → "assassin"`, so the first player to reach 0 life ends the
    // game for the whole table. The win check must be gated on the game mode
    // including treachery.
    test.fixme(
      'a player hitting 0 life does not end the game for everyone else',
      async ({ browser }) => {
        const { gameId, players } = await setupNonTreacheryGame(browser, 4, mode, {
          startingLife: STARTING_LIFE,
        });
        const [p1, p2, p3, p4] = players;

        // p1 knocks p2 out.
        await damage(p1.page, p2.name, STARTING_LIFE);
        await expectServerLife(p1.page, gameId, p2.userId, 0);

        await expect
          .poll(async () => (await fetchPlayerDocs(p1.page, gameId)).find((d) => d.user_id === p2.userId)?.is_eliminated)
          .toBe(true);

        // The game must still be running, with no winner declared.
        const game = await fetchGameDoc(p1.page, gameId);
        expect(game?.state).toBe('in_progress');
        expect(game?.winning_team ?? null).toBeNull();

        // Nobody got bounced to the game-over screen.
        for (const p of players) {
          await expect(p.page).toHaveURL(/\/game\//);
        }

        // And the survivors keep playing.
        await damage(p3.page, p4.name, 3);
        await expectServerLife(p3.page, gameId, p4.userId, STARTING_LIFE - 3);
        expect((await fetchGameDoc(p1.page, gameId))?.state).toBe('in_progress');
      },
    );

    test('the host can end the game explicitly', async ({ browser }) => {
      const { gameId, players, host } = await setupNonTreacheryGame(browser, 4, mode, {
        startingLife: STARTING_LIFE,
      });

      // End Game is host-only in non-treachery modes.
      await expect(players[1].page.getByRole('button', { name: 'End game' })).toHaveCount(0);

      await host.page.getByRole('button', { name: 'End game' }).click();
      // Winner selection modal — skip picking anyone and just end it.
      await host.page
        .getByRole('button', { name: 'End game' })
        .last()
        .click();

      await Promise.all(
        players.map((p) => expect(p.page).toHaveURL(/\/game-over\//, { timeout: 20_000 })),
      );
      expect((await fetchGameDoc(host.page, gameId))?.state).toBe('finished');

      // The non-treachery game-over screen is a life-total summary — it must
      // not pretend there were teams.
      await expect(host.page.getByText(/Session ended with 4 players/)).toBeVisible();
    });
  });
}
