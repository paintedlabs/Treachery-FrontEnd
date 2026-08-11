import { Browser, Page, test, expect } from '@playwright/test';
import {
  PlayerHandle,
  Role,
  damage,
  expectServerLife,
  fetchGameDoc,
  forfeit,
  playerWithRole,
  playersWithRole,
  setupSeededGame,
  unveilSelf,
} from './helpers';

/**
 * Negative visibility — the "must NOT see" half of a hidden-role game.
 *
 * Everything else in the suite asserts that the right thing appears. This file
 * asserts that the wrong thing doesn't: a concealed player's role and card
 * must be invisible to everyone else, and the game-over screen's full identity
 * reveal must be unreachable while the game is still being played.
 */

const LAYOUT: Role[] = ['leader', 'assassin', 'assassin', 'traitor'];
// A stable, unique card name to grep for. If this string is ever visible to
// someone who shouldn't see it, the hidden-role game is broken.
const TRAITOR_CARD = 'traitor_01';
const TRAITOR_CARD_NAME = 'The Banisher';
const STARTING_LIFE = 20;

const roleButton = (page: Page, role: string) =>
  // PlayerRow labels the role line "<Role> role[, view card]" — and renders
  // "Role Hidden" instead when the identity is still concealed.
  page.getByRole('button', { name: new RegExp(`^${role} role`) });

/** Nothing on this page may give away the concealed traitor's identity. */
async function expectNoTraitorLeak(page: Page) {
  await expect(page.getByText(TRAITOR_CARD_NAME)).toHaveCount(0);
  await expect(page.getByText('Traitor')).toHaveCount(0);
}

test.describe('Concealed identities stay concealed', () => {
  test('every non-leader role is hidden from the rest of the table until unveiled', async ({
    browser,
  }) => {
    const { players } = await setupSeededGame(browser, LAYOUT, {
      cardOverrides: { 3: TRAITOR_CARD },
      startingLife: STARTING_LIFE,
    });
    const traitor = playerWithRole(players, 'traitor');

    for (const viewer of players) {
      // Leader is public to everyone. Non-leaders only see their *own* role
      // on the roster (plus identity card in the header) — never each other.
      await expect(roleButton(viewer.page, 'Leader')).toHaveCount(1);
      await expect(roleButton(viewer.page, 'Assassin')).toHaveCount(
        viewer.role === 'assassin' ? 1 : 0,
      );
      await expect(roleButton(viewer.page, 'Guardian')).toHaveCount(
        viewer.role === 'guardian' ? 1 : 0,
      );
      await expect(roleButton(viewer.page, 'Traitor')).toHaveCount(
        viewer.role === 'traitor' ? 1 : 0,
      );
      // Non-leaders for this viewer minus self (if viewer is non-leader).
      const hiddenCount = LAYOUT.length - 1 - (viewer.role === 'leader' ? 0 : 1);
      await expect(viewer.page.getByText('Role Hidden')).toHaveCount(hiddenCount);
    }

    // The traitor's *card* is likewise invisible to the other three boards.
    for (const viewer of players.filter((p) => p.userId !== traitor.userId)) {
      await expect(viewer.page.getByText(TRAITOR_CARD_NAME)).toHaveCount(0);
    }

    // Unveiling is the only thing that flips it — and only for that player.
    await unveilSelf(traitor.page);
    for (const viewer of players) {
      await expect(roleButton(viewer.page, 'Traitor')).toHaveCount(1);
      // Assassins still only see themselves (not the other assassin).
      await expect(roleButton(viewer.page, 'Assassin')).toHaveCount(
        viewer.role === 'assassin' ? 1 : 0,
      );
      // Two assassins still hidden for non-assassins; one for an assassin viewer.
      const hiddenCount = viewer.role === 'assassin' ? 1 : 2;
      await expect(viewer.page.getByText('Role Hidden')).toHaveCount(hiddenCount);
    }
  });
});

test.describe('The game-over reveal is unreachable mid-game', () => {
  // Full identity reveal is gated on game.state === finished. Each route
  // below used to leak; assert none of them hand over roles mid-game.

  async function setup(browser: Browser) {
    return setupSeededGame(browser, LAYOUT, {
      cardOverrides: { 3: TRAITOR_CARD },
      startingLife: STARTING_LIFE,
    });
  }

  // Spectator "Leave game" returns home — never mid-game game-over reveal.
  test('an eliminated spectator pressing Leave Game sees no identities', async ({ browser }) => {
    const { players, gameId } = await setup(browser);
    const leader = playerWithRole(players, 'leader');
    const [assassinA] = playersWithRole(players, 'assassin');

    await damage(leader.page, assassinA.name, STARTING_LIFE);
    await expectServerLife(leader.page, gameId, assassinA.userId, 0);

    await assassinA.page.getByRole('button', { name: 'Leave game' }).click();

    // The game is still running for everyone else...
    expect((await fetchGameDoc(leader.page, gameId))?.state).toBe('in_progress');
    // ...so the eliminated player must not be handed the full reveal.
    await expectNoTraitorLeak(assassinA.page);
  });

  // Forfeit stays on the board as spectator until the game actually ends.
  test('a player who forfeits while the game continues sees no identities', async ({
    browser,
  }) => {
    const { players, gameId } = await setup(browser);
    const [assassinA] = playersWithRole(players, 'assassin');

    await forfeit(assassinA.page);
    await expect(assassinA.page).toHaveURL(/\/game\//, { timeout: 15_000 });
    await expect(assassinA.page.getByRole('button', { name: 'Leave game' })).toBeVisible({
      timeout: 15_000,
    });

    // Leader + one assassin + traitor are still alive, so nobody has won.
    expect((await fetchGameDoc(players[0].page, gameId))?.state).toBe('in_progress');
    await expectNoTraitorLeak(assassinA.page);
  });

  // Deep link mid-game shows a hold screen, not the identity table.
  test('navigating directly to /game-over mid-game reveals nothing', async ({ browser }) => {
    const { players, gameId } = await setup(browser);
    const snoop: PlayerHandle = playersWithRole(players, 'assassin')[0];

    expect((await fetchGameDoc(snoop.page, gameId))?.state).toBe('in_progress');
    await snoop.page.goto(`/game-over/${gameId}`);
    await expect(snoop.page.getByText('Game Still In Progress')).toBeVisible({
      timeout: 20_000,
    });

    await expectNoTraitorLeak(snoop.page);
  });
});
