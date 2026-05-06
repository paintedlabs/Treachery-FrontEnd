import { Browser, Page, expect } from '@playwright/test';

export type Role = 'leader' | 'guardian' | 'assassin' | 'traitor';

export interface RoleAssignment {
  role: Role;
  identityCardId: string;
}

export interface TestSeed {
  assignments: Record<string, RoleAssignment>;
}

export interface PlayerHandle {
  /** Display name shown in the lobby and game UI ("Player 1", "Player 2", ...). */
  name: string;
  page: Page;
  userId: string;
  role: Role;
  identityCardId: string;
}

export interface SeededGame {
  players: PlayerHandle[];
  host: PlayerHandle;
  gameId: string;
  code: string;
}

// Role distribution per player count — must mirror getRoleDistribution in
// functions/index.js. Tests assert against these counts.
export const ROLE_DISTRIBUTION: Record<number, Record<Role, number>> = {
  4: { leader: 1, guardian: 0, assassin: 2, traitor: 1 },
  5: { leader: 1, guardian: 1, assassin: 2, traitor: 1 },
  6: { leader: 1, guardian: 1, assassin: 3, traitor: 1 },
  7: { leader: 1, guardian: 2, assassin: 3, traitor: 1 },
  8: { leader: 1, guardian: 2, assassin: 3, traitor: 2 },
};

// Predictable card IDs so tests can override specific cards (e.g. force the
// traitor onto traitor_07 for the Metamorph spec).
const CARDS_BY_ROLE: Record<Role, string[]> = {
  leader: Array.from({ length: 13 }, (_, i) => `leader_${String(i + 1).padStart(2, '0')}`),
  guardian: Array.from({ length: 18 }, (_, i) => `guardian_${String(i + 1).padStart(2, '0')}`),
  assassin: Array.from({ length: 18 }, (_, i) => `assassin_${String(i + 1).padStart(2, '0')}`),
  traitor: Array.from({ length: 13 }, (_, i) => `traitor_${String(i + 1).padStart(2, '0')}`),
};

// ── Auth + lobby ─────────────────────────────────────────────────

export async function signInAsGuest(page: Page) {
  await page.goto('/');
  await page.getByRole('button', { name: 'Play as Guest' }).click();
  // Onboarding: display name (default ok), welcome
  await page.getByRole('button', { name: 'Continue' }).click();
  await page.getByRole('button', { name: "Let's Play" }).click();
  await expect(page.getByRole('button', { name: 'Create game' })).toBeVisible({ timeout: 20_000 });
}

export async function hostCreateGame(page: Page): Promise<{ gameId: string; code: string }> {
  await page.getByRole('button', { name: 'Create game' }).click();
  await expect(page).toHaveURL(/\/create-game/);
  await page.getByRole('button', { name: 'Create game' }).click();
  await expect(page).toHaveURL(/\/lobby\//);
  const gameId = parseGameIdFromUrl(page.url());
  const code = (
    await page.getByText(/^[A-Z0-9]{4}$/).first().textContent()
  )?.trim();
  if (!code || !/^[A-Z0-9]{4}$/.test(code)) {
    throw new Error(`Failed to read game code from lobby (got ${JSON.stringify(code)})`);
  }
  return { gameId, code };
}

export async function guestJoinGame(page: Page, code: string) {
  await page.getByRole('button', { name: 'Join game' }).click();
  await expect(page).toHaveURL(/\/join-game/);
  await page.getByLabel('Game code').fill(code);
  await page.getByRole('button', { name: 'Join game' }).click();
  await expect(page).toHaveURL(/\/lobby\//);
}

function parseGameIdFromUrl(url: string): string {
  const match = url.match(/\/(lobby|game)\/([^/?#]+)/);
  if (!match) throw new Error(`Could not parse gameId from URL: ${url}`);
  return decodeURIComponent(match[2]);
}

// ── E2E bridge (window.__e2e exposed by firebase config in emulator mode) ──

async function getCurrentUserId(page: Page): Promise<string> {
  const uid = await page.evaluate(() => {
    const e2e = (window as unknown as { __e2e?: { getCurrentUserId: () => string | null } }).__e2e;
    if (!e2e) throw new Error('window.__e2e missing — was the bundle built with EXPO_PUBLIC_USE_EMULATOR=true?');
    return e2e.getCurrentUserId();
  });
  if (!uid) throw new Error('No authenticated user in this page context');
  return uid;
}

async function callStartGameWithSeed(hostPage: Page, gameId: string, seed: TestSeed) {
  await hostPage.evaluate(
    async ({ gameId, seed }) => {
      const e2e = (window as unknown as {
        __e2e?: { startGameWithSeed: (gid: string, seed: unknown) => Promise<unknown> };
      }).__e2e;
      if (!e2e) throw new Error('window.__e2e missing');
      await e2e.startGameWithSeed(gameId, seed);
    },
    { gameId, seed },
  );
}

// ── Test seed construction ───────────────────────────────────────

/**
 * Build a {@link TestSeed} that maps each player's user_id to a role and
 * identity card. The role layout array's length must match the number of
 * players, and the role counts must match the distribution for that count.
 *
 * `cardOverrides` lets tests force a specific card by player index (the
 * Metamorph spec uses this to put the traitor on `traitor_07`).
 */
export function buildTestSeed(
  userIds: string[],
  layout: Role[],
  cardOverrides: Record<number, string> = {},
): TestSeed {
  if (userIds.length !== layout.length) {
    throw new Error(`userIds (${userIds.length}) and layout (${layout.length}) length mismatch`);
  }
  const usedCards = new Set<string>();
  const assignments: Record<string, RoleAssignment> = {};
  const cursors: Record<Role, number> = { leader: 0, guardian: 0, assassin: 0, traitor: 0 };

  for (let i = 0; i < userIds.length; i++) {
    const role = layout[i];
    let cardId: string;
    if (cardOverrides[i]) {
      cardId = cardOverrides[i];
      if (!cardId.startsWith(`${role}_`)) {
        throw new Error(`Card override for index ${i} (${cardId}) does not match role ${role}`);
      }
    } else {
      // Pick the first unused card for this role.
      const pool = CARDS_BY_ROLE[role];
      while (cursors[role] < pool.length && usedCards.has(pool[cursors[role]])) {
        cursors[role]++;
      }
      if (cursors[role] >= pool.length) {
        throw new Error(`Ran out of ${role} cards`);
      }
      cardId = pool[cursors[role]++];
    }
    if (usedCards.has(cardId)) {
      throw new Error(`Card ${cardId} assigned twice`);
    }
    usedCards.add(cardId);
    assignments[userIds[i]] = { role, identityCardId: cardId };
  }
  return { assignments };
}

// ── High-level bootstrap ─────────────────────────────────────────

interface SetupOptions {
  /** Map of player index → forced identity card id (e.g. { 3: 'traitor_07' } for the Metamorph). */
  cardOverrides?: Record<number, string>;
}

/**
 * End-to-end bootstrap: spawns one browser context per player, signs each in
 * as a guest, has player 0 host a game, has the rest join, then starts the
 * game with deterministic role/card assignments (via the emulator-only
 * window.__e2e.startGameWithSeed bridge). Returns handles to each player's
 * page along with their assigned role.
 *
 * Player 0 is the host. The roles array is positional — `roles[i]` is the role
 * given to player i. The role counts must match ROLE_DISTRIBUTION[roles.length].
 */
export async function setupSeededGame(
  browser: Browser,
  roles: Role[],
  options: SetupOptions = {},
): Promise<SeededGame> {
  const playerCount = roles.length;
  if (!ROLE_DISTRIBUTION[playerCount]) {
    throw new Error(`Unsupported player count: ${playerCount}`);
  }
  // Validate role counts.
  const counts: Record<Role, number> = { leader: 0, guardian: 0, assassin: 0, traitor: 0 };
  for (const r of roles) counts[r]++;
  const expected = ROLE_DISTRIBUTION[playerCount];
  for (const r of ['leader', 'guardian', 'assassin', 'traitor'] as Role[]) {
    if (counts[r] !== expected[r]) {
      throw new Error(
        `Role layout for ${playerCount} players has wrong counts: got ${JSON.stringify(counts)}, expected ${JSON.stringify(expected)}`,
      );
    }
  }

  // Spin up contexts and pages, one per player.
  const contexts = await Promise.all(
    Array.from({ length: playerCount }, () => browser.newContext()),
  );
  const pages = await Promise.all(contexts.map((c) => c.newPage()));

  // Sign all in in parallel.
  await Promise.all(pages.map(signInAsGuest));

  // Host creates, guests join.
  const [hostPage, ...guestPages] = pages;
  const { gameId, code } = await hostCreateGame(hostPage);
  await Promise.all(guestPages.map((p) => guestJoinGame(p, code)));

  // Wait for the host to see all players in the lobby.
  await expect(hostPage.getByText(`Players (${playerCount})`)).toBeVisible();

  // Read each player's user_id (preserves the order they joined: host first).
  const userIds = await Promise.all(pages.map(getCurrentUserId));

  // Build seed and start the game via the emulator bridge.
  const seed = buildTestSeed(userIds, roles, options.cardOverrides);
  await callStartGameWithSeed(hostPage, gameId, seed);

  // Wait for all players to navigate to the game board.
  await Promise.all(pages.map((p) => expect(p).toHaveURL(/\/game\//, { timeout: 20_000 })));

  const players: PlayerHandle[] = pages.map((page, i) => {
    const userId = userIds[i];
    const assignment = seed.assignments[userId];
    return {
      name: `Player ${i + 1}`, // matches the default display_name pattern after onboarding
      page,
      userId,
      role: assignment.role,
      identityCardId: assignment.identityCardId,
    };
  });

  return { players, host: players[0], gameId, code };
}

// ── In-game actions ──────────────────────────────────────────────

/**
 * Decrease another player's life total by `amount` via the per-row -1 button.
 * Each click fires an `adjustLife` cloud function call.
 */
export async function damage(actor: Page, targetName: string, amount: number) {
  const button = actor.getByRole('button', { name: `Decrease ${targetName} life` });
  for (let i = 0; i < amount; i++) {
    await button.click();
  }
}

/**
 * Drives a player's life to 0 by clicking -1 enough times. The lobby reads
 * starting life from the game doc; `startingLife` defaults to 40 (the
 * single-game-mode default in the create-game screen).
 */
export async function eliminateByDamage(actor: Page, targetName: string, startingLife = 40) {
  await damage(actor, targetName, startingLife);
}

/** Click Unveil and confirm the window.confirm dialog. */
export async function unveilSelf(page: Page) {
  page.once('dialog', (d) => d.accept());
  await page.getByRole('button', { name: 'Unveil identity' }).click();
}

/** Click Forfeit and confirm. */
export async function forfeit(page: Page) {
  page.once('dialog', (d) => d.accept());
  await page.getByRole('button', { name: 'Forfeit' }).click();
}

/**
 * Wait for all pages to navigate to the game-over screen and assert the
 * winning team text is present on at least the first page.
 */
export async function expectWinner(pages: Page[], team: 'Leader' | 'Assassin' | 'Traitor') {
  await Promise.all(
    pages.map((p) => expect(p).toHaveURL(/\/game-over\//, { timeout: 30_000 })),
  );
  // The game-over screen renders the winning team's display name.
  // Match permissively: "Leader", "Leader/Guardian", "Assassins", "Traitor", etc.
  const re = new RegExp(team, 'i');
  await expect(pages[0].getByText(re).first()).toBeVisible();
}

/** Find the player handle in `players` whose role matches `role`. */
export function playerWithRole(players: PlayerHandle[], role: Role): PlayerHandle {
  const found = players.find((p) => p.role === role);
  if (!found) throw new Error(`No player with role '${role}' in this seed`);
  return found;
}

/** Find all players with the given role. */
export function playersWithRole(players: PlayerHandle[], role: Role): PlayerHandle[] {
  return players.filter((p) => p.role === role);
}

/**
 * Read all player docs from `/games/{gameId}/players` using one of the
 * authenticated browser contexts. Useful for asserting on identity-card and
 * is_face_down state after an ability resolves.
 */
export async function fetchPlayerDocs(
  page: Page,
  gameId: string,
): Promise<Array<{ id: string; user_id: string; identity_card_id: string | null; role: Role | null; is_eliminated?: boolean; is_unveiled?: boolean; is_face_down?: boolean; original_identity_card_id?: string | null }>> {
  return page.evaluate(async ({ gameId }) => {
    const e2e = (window as unknown as {
      __e2e?: { fetchPlayers: (gid: string) => Promise<unknown[]> };
    }).__e2e;
    if (!e2e) throw new Error('window.__e2e missing');
    return e2e.fetchPlayers(gameId);
  }, { gameId }) as Promise<Array<{ id: string; user_id: string; identity_card_id: string | null; role: Role | null; is_eliminated?: boolean; is_unveiled?: boolean; is_face_down?: boolean; original_identity_card_id?: string | null }>>;
}
