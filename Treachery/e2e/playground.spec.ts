import { test, expect } from '@playwright/test';
import {
  GameMode,
  PlayerHandle,
  ROLE_DISTRIBUTION,
  Role,
  setupLobby,
  setupNonTreacheryGame,
  setupSeededGame,
} from './helpers';

/**
 * Manual playtest harness — NOT a test.
 *
 * Opens one real, signed-in browser window per player, walks them into a
 * lobby (and optionally starts the game), prints who is who, then parks on
 * `page.pause()` so you can click around by hand. It replaces opening N
 * browsers and signing into each one.
 *
 * Run it:
 *
 *   npm run playtest                      # 4-player treachery, seeded roles
 *   PLAYTEST_PLAYERS=6 npm run playtest
 *   PLAYTEST_MODE=none npm run playtest   # Life Tracker
 *   PLAYTEST_START=lobby npm run playtest # stop in the lobby, don't start
 *   PLAYTEST_START=real npm run playtest  # real Start button, random roles
 *   npm run playtest:nobuild              # skip the web rebuild (~30s faster)
 *
 *   PLAYTEST_PLAYERS  4-8                       (default 4)
 *   PLAYTEST_MODE     treachery | treachery_planechase | planechase | none
 *                                               (default treachery)
 *   PLAYTEST_LIFE     multiple of 5             (default 40)
 *   PLAYTEST_START    seeded | real | lobby     (default seeded)
 *
 * This file is excluded from the CI suite (see `testIgnore` in
 * playwright.config.ts) — it never terminates on its own, by design.
 */

const PLAYERS = Number.parseInt(process.env.PLAYTEST_PLAYERS ?? '4', 10);
const MODE = (process.env.PLAYTEST_MODE ?? 'treachery') as GameMode;
const LIFE = Number.parseInt(process.env.PLAYTEST_LIFE ?? '40', 10);
const START = (process.env.PLAYTEST_START ?? 'seeded') as 'seeded' | 'real' | 'lobby';

const IS_TREACHERY = MODE === 'treachery' || MODE === 'treachery_planechase';

/**
 * Expand the role distribution for a player count into a positional layout.
 * Deterministic on purpose: player 1 (the host) is always the Leader, so you
 * know where to look without hunting. Use PLAYTEST_START=real for a genuinely
 * random assignment.
 */
function roleLayout(playerCount: number): Role[] {
  const dist = ROLE_DISTRIBUTION[playerCount];
  if (!dist) throw new Error(`Unsupported player count: ${playerCount} (4-8)`);
  const layout: Role[] = [];
  (['leader', 'guardian', 'assassin', 'traitor'] as Role[]).forEach((role) => {
    for (let i = 0; i < dist[role]; i++) layout.push(role);
  });
  return layout;
}

function banner(lines: string[]) {
  const width = Math.max(...lines.map((l) => l.length));
  console.log(`\n┌${'─'.repeat(width + 2)}┐`);
  for (const l of lines) console.log(`│ ${l.padEnd(width)} │`);
  console.log(`└${'─'.repeat(width + 2)}┘\n`);
}

test('playground', async ({ browser }) => {
  if (IS_TREACHERY && START === 'seeded' && (PLAYERS < 4 || PLAYERS > 8)) {
    throw new Error(
      `Seeded treachery needs 4-8 players (got ${PLAYERS}). ` +
        `Use PLAYTEST_START=real or PLAYTEST_START=lobby for other counts.`,
    );
  }

  let players: PlayerHandle[];
  let gameId: string;
  let code: string;

  if (START === 'lobby') {
    const lobby = await setupLobby(browser, PLAYERS, { mode: MODE, startingLife: LIFE });
    ({ gameId, code } = lobby);
    players = lobby.pages.map((page, i) => ({
      name: lobby.names[i],
      page,
      userId: lobby.userIds[i],
      role: null,
      identityCardId: null,
    }));
  } else if (!IS_TREACHERY) {
    const game = await setupNonTreacheryGame(
      browser,
      PLAYERS,
      MODE as Exclude<GameMode, 'treachery' | 'treachery_planechase'>,
      { startingLife: LIFE },
    );
    ({ players, gameId, code } = game);
  } else if (START === 'real') {
    // Real Start button: the server assigns roles and cards at random, which
    // is what you want when you're eyeballing the actual dealing logic.
    const lobby = await setupLobby(browser, PLAYERS, { mode: MODE, startingLife: LIFE });
    const [hostPage] = lobby.pages;
    await expect(hostPage.getByRole('button', { name: 'Start game' })).toBeEnabled();
    await hostPage.getByRole('button', { name: 'Start game' }).click();
    await Promise.all(
      lobby.pages.map((p) => expect(p).toHaveURL(/\/game\//, { timeout: 20_000 })),
    );
    ({ gameId, code } = lobby);
    players = lobby.pages.map((page, i) => ({
      name: lobby.names[i],
      page,
      userId: lobby.userIds[i],
      role: null, // assigned server-side; unknown to us here
      identityCardId: null,
    }));
  } else {
    const game = await setupSeededGame(browser, roleLayout(PLAYERS), { startingLife: LIFE });
    ({ players, gameId, code } = game);
  }

  // Playwright auto-DISMISSES native dialogs (window.confirm etc.) unless a
  // handler is registered — so a human clicking Unveil/Forfeit/Leave in a
  // playground window would have the confirm silently answered "Cancel"
  // before it even renders. Auto-accept instead: in a disposable playtest
  // game, "are you sure?" is always yes. (The real fix is the in-app confirm
  // dialog — once no native dialogs remain, this handler simply never fires.)
  for (const p of players) {
    p.page.on('dialog', (d) => void d.accept());
  }

  banner([
    `game code   ${code}`,
    `mode        ${MODE}`,
    `players     ${PLAYERS}`,
    `life        ${LIFE}`,
    `start       ${START}`,
    `gameId      ${gameId}`,
    '',
    ...players.map((p) => {
      const who = p.role ? `${p.role}${p.identityCardId ? ` (${p.identityCardId})` : ''}` : '—';
      return `${p.name.padEnd(10)} ${who}`;
    }),
    '',
    'All windows are signed in and live. Click around.',
    'Press Resume in the Playwright Inspector, or close it, to tear down.',
  ]);

  // Parks here indefinitely (timeout is 0 in the playground config) with every
  // browser window interactive.
  await players[0].page.pause();
});
