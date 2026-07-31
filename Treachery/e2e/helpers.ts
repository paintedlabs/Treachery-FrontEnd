import { Browser, Page, expect } from '@playwright/test';

export type Role = 'leader' | 'guardian' | 'assassin' | 'traitor';

/** Mirrors GameMode in src/models/types.ts. */
export type GameMode = 'treachery' | 'planechase' | 'treachery_planechase' | 'none';

// The create-game screen labels its mode buttons, not its mode values, so the
// accessibility label we click is derived from this map (see GAME_MODES in
// app/(app)/create-game.tsx).
const MODE_BUTTON_LABEL: Record<GameMode, string> = {
  treachery: 'Treachery',
  planechase: 'Planechase',
  treachery_planechase: 'Both',
  none: 'Life Tracker',
};

/** Starting-life values the lobby's updateGameSettings accepts. */
export const STARTING_LIFE_VALUES = [20, 25, 30, 40, 50] as const;
export type StartingLife = (typeof STARTING_LIFE_VALUES)[number];

/** The create-game screen's default, used whenever a test doesn't override it. */
export const DEFAULT_STARTING_LIFE = 40;

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
  /** null in non-treachery modes, where startGame assigns no roles. */
  role: Role | null;
  /** null in non-treachery modes, where startGame assigns no identity cards. */
  identityCardId: string | null;
}

export interface SeededGame {
  players: PlayerHandle[];
  host: PlayerHandle;
  gameId: string;
  code: string;
  /** Game mode the lobby was created with — 'treachery' unless overridden. */
  mode: GameMode;
  /** starting_life written onto the game doc (before per-card life modifiers). */
  startingLife: number;
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

export async function signInAsGuest(page: Page, displayName?: string) {
  await page.goto('/');
  await page.getByRole('button', { name: 'Play as Guest' }).click();
  // Onboarding: optionally override the default "Guest" display name so
  // tests can disambiguate players in UI selectors (e.g. the Puppet Master
  // modal's "Swap with {display_name}" buttons).
  if (displayName) {
    const input = page.getByLabel('Display name');
    await input.fill(displayName);
  }
  await page.getByRole('button', { name: 'Continue' }).click();
  await page.getByRole('button', { name: "Let's Play" }).click();
  await expect(page.getByRole('button', { name: 'Create game' })).toBeVisible({ timeout: 20_000 });
}

export interface CreateGameOptions {
  /** Game mode chip to select on the create screen. Defaults to 'treachery'. */
  mode?: GameMode;
  /**
   * Starting life to dial in with the create screen's stepper (default 40,
   * ±5 per tap). Lower values keep tests fast: eliminating a player means
   * clicking `-1` once per point of life.
   */
  startingLife?: number;
}

export async function hostCreateGame(
  page: Page,
  options: CreateGameOptions = {},
): Promise<{ gameId: string; code: string }> {
  await page.getByRole('button', { name: 'Create game' }).click();
  await expect(page).toHaveURL(/\/create-game/);

  if (options.mode && options.mode !== 'treachery') {
    await page
      .getByRole('button', { name: `${MODE_BUTTON_LABEL[options.mode]} game mode` })
      .click();
  }

  if (options.startingLife !== undefined && options.startingLife !== DEFAULT_STARTING_LIFE) {
    const delta = options.startingLife - DEFAULT_STARTING_LIFE;
    if (delta % 5 !== 0) {
      throw new Error(`startingLife must be a multiple of 5 (got ${options.startingLife})`);
    }
    const label = delta < 0 ? 'Decrease starting life' : 'Increase starting life';
    for (let i = 0; i < Math.abs(delta) / 5; i++) {
      await page.getByRole('button', { name: label }).click();
    }
    await expect(page.getByText(`Starting Life: ${options.startingLife}`)).toBeVisible();
  }

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
  // Specs join guests concurrently (Promise.all), and every joinGame call runs
  // a transaction against the same game doc, so they serialize and retry under
  // contention — an 8-player join has been measured at ~9.5s in the emulator,
  // right at the 10s default. Give it the same headroom signInAsGuest uses
  // rather than letting a slow-but-successful join read as a failure.
  await expect(page).toHaveURL(/\/lobby\//, { timeout: 20_000 });
}

function parseGameIdFromUrl(url: string): string {
  const match = url.match(/\/(lobby|game)\/([^/?#]+)/);
  if (!match) throw new Error(`Could not parse gameId from URL: ${url}`);
  return decodeURIComponent(match[2]);
}

// ── E2E bridge (window.__e2e exposed by firebase config in emulator mode) ──

export async function getCurrentUserId(page: Page): Promise<string> {
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

export interface SetupOptions {
  /** Map of player index → forced identity card id (e.g. { 3: 'traitor_07' } for the Metamorph). */
  cardOverrides?: Record<number, string>;
  /** Passed through to the create-game screen's stepper. Defaults to 40. */
  startingLife?: number;
}

export interface LobbyHandle {
  /** One page per player, in join order (index 0 is the host). */
  pages: Page[];
  userIds: string[];
  names: string[];
  gameId: string;
  code: string;
  mode: GameMode;
  startingLife: number;
}

/**
 * Everything up to (but not including) the game start: N guest contexts signed
 * in as "Player 1".."Player N", player 0 hosting, the rest joined by code.
 *
 * Split out of {@link setupSeededGame} so lobby-only specs (host promotion,
 * settings) can drive the pre-game state without starting anything, and so
 * non-treachery modes can reuse the same bootstrap.
 */
export async function setupLobby(
  browser: Browser,
  playerCount: number,
  options: CreateGameOptions = {},
): Promise<LobbyHandle> {
  const contexts = await Promise.all(
    Array.from({ length: playerCount }, () => browser.newContext()),
  );
  const pages = await Promise.all(contexts.map((c) => c.newPage()));

  // Sign all in in parallel, each with a unique display name. The names
  // ("Player 1", "Player 2", ...) make modal selectors deterministic
  // (e.g. the Puppet Master swap rows are labeled by display_name).
  const names = pages.map((_, i) => `Player ${i + 1}`);
  await Promise.all(pages.map((p, i) => signInAsGuest(p, names[i])));

  const [hostPage, ...guestPages] = pages;
  const { gameId, code } = await hostCreateGame(hostPage, options);
  // Join sequentially: joinGame assigns order_id from the current player count
  // inside a transaction, so parallel joins are safe but the resulting seat
  // order is not deterministic. Tests index players by seat, so keep it stable.
  for (const p of guestPages) {
    await guestJoinGame(p, code);
  }

  // Wait for the host to see all players in the lobby.
  await expect(hostPage.getByText(`Players (${playerCount})`)).toBeVisible();

  // Read each player's user_id (preserves the order they joined: host first).
  const userIds = await Promise.all(pages.map(getCurrentUserId));

  return {
    pages,
    userIds,
    names,
    gameId,
    code,
    mode: options.mode ?? 'treachery',
    startingLife: options.startingLife ?? DEFAULT_STARTING_LIFE,
  };
}

/**
 * Bootstrap a *non-treachery* game (planechase / Life Tracker) through the real
 * UI, including the lobby's Start button. There are no roles or identity cards
 * in these modes, so there's nothing to seed — this is the only path that
 * exercises startGame's `includesTreachery === false` branch end to end.
 */
export async function setupNonTreacheryGame(
  browser: Browser,
  playerCount: number,
  mode: Exclude<GameMode, 'treachery' | 'treachery_planechase'>,
  options: { startingLife?: number } = {},
): Promise<SeededGame> {
  const lobby = await setupLobby(browser, playerCount, { mode, ...options });
  const [hostPage] = lobby.pages;

  await expect(hostPage.getByRole('button', { name: 'Start game' })).toBeEnabled();
  await hostPage.getByRole('button', { name: 'Start game' }).click();
  await Promise.all(
    lobby.pages.map((p) => expect(p).toHaveURL(/\/game\//, { timeout: 20_000 })),
  );

  const players: PlayerHandle[] = lobby.pages.map((page, i) => ({
    name: lobby.names[i],
    page,
    userId: lobby.userIds[i],
    // Non-treachery games leave role/identity_card_id null on every player.
    role: null,
    identityCardId: null,
  }));

  return {
    players,
    host: players[0],
    gameId: lobby.gameId,
    code: lobby.code,
    mode,
    startingLife: lobby.startingLife,
  };
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

  const { pages, userIds, names, gameId, code, startingLife } = await setupLobby(
    browser,
    playerCount,
    { startingLife: options.startingLife },
  );

  // Build seed and start the game via the emulator bridge.
  const seed = buildTestSeed(userIds, roles, options.cardOverrides);
  await callStartGameWithSeed(pages[0], gameId, seed);

  // Wait for all players to navigate to the game board.
  await Promise.all(pages.map((p) => expect(p).toHaveURL(/\/game\//, { timeout: 20_000 })));

  const players: PlayerHandle[] = pages.map((page, i) => {
    const userId = userIds[i];
    const assignment = seed.assignments[userId];
    return {
      name: names[i], // matches the display_name set during onboarding
      page,
      userId,
      role: assignment.role,
      identityCardId: assignment.identityCardId,
    };
  });

  return { players, host: players[0], gameId, code, mode: 'treachery', startingLife };
}

// ── In-game actions ──────────────────────────────────────────────

/**
 * Decrease another player's life total by `amount` via the per-row -1 button.
 *
 * NOTE: taps are debounced ~500ms in useGameBoard and collapsed into a single
 * `adjustLife` call, so N clicks in quick succession are one cloud-function
 * call of -N. Anything asserting on the *server* total must wait out that
 * debounce — use {@link expectServerLife}.
 */
export async function damage(actor: Page, targetName: string, amount: number) {
  const button = actor.getByRole('button', { name: `Decrease ${targetName} life` });
  for (let i = 0; i < amount; i++) {
    await button.click();
  }
}

/** Increase another player's life total by `amount` via the per-row +1 button. */
export async function heal(actor: Page, targetName: string, amount: number) {
  const button = actor.getByRole('button', { name: `Increase ${targetName} life` });
  for (let i = 0; i < amount; i++) {
    await button.click();
  }
}

/** How long useGameBoard waits after the last tap before flushing to the server. */
export const LIFE_DEBOUNCE_MS = 500;

/**
 * Drives a player's life to 0 by clicking -1 enough times. The lobby reads
 * starting life from the game doc; `startingLife` defaults to 40 (the
 * single-game-mode default in the create-game screen).
 */
export async function eliminateByDamage(actor: Page, targetName: string, startingLife = 40) {
  await damage(actor, targetName, startingLife);
}

/** Click Unveil and accept the in-app confirmation dialog. */
export async function unveilSelf(page: Page) {
  await page.getByRole('button', { name: 'Unveil identity' }).click();
  await page.getByRole('button', { name: 'Confirm unveil' }).click();
}

/** Click Forfeit and accept the in-app confirmation dialog. */
export async function forfeit(page: Page) {
  await page.getByRole('button', { name: 'Forfeit', exact: true }).click();
  await page.getByRole('button', { name: 'Confirm forfeit' }).click();
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

/** Shape of a `/games/{gameId}` doc as read back through the E2E bridge. */
export interface ServerGame extends Record<string, unknown> {
  id: string;
  state?: 'waiting' | 'in_progress' | 'finished';
  host_id?: string;
  game_mode?: GameMode;
  starting_life?: number;
  winning_team?: Role | null;
  player_ids?: string[];
  max_traitor_rarity?: string;
}

/** Shape of a `/games/{gameId}/players/{playerId}` doc. */
export interface ServerPlayer {
  id: string;
  user_id: string;
  display_name?: string;
  order_id?: number;
  identity_card_id: string | null;
  role: Role | null;
  life_total?: number;
  is_eliminated?: boolean;
  is_unveiled?: boolean;
  is_face_down?: boolean;
  original_identity_card_id?: string | null;
  original_role?: Role | null;
}

/**
 * Read the game doc itself using one of the authenticated browser contexts.
 * Useful for asserting host settings (e.g. max_traitor_rarity) persisted.
 */
export async function fetchGameDoc(page: Page, gameId: string): Promise<ServerGame | null> {
  return page.evaluate(
    async ({ gameId }) => {
      const e2e = (window as unknown as {
        __e2e?: { fetchGame: (gid: string) => Promise<unknown> };
      }).__e2e;
      if (!e2e) throw new Error('window.__e2e missing');
      return e2e.fetchGame(gameId);
    },
    { gameId },
  ) as Promise<ServerGame | null>;
}

/**
 * Read all player docs from `/games/{gameId}/players` using one of the
 * authenticated browser contexts. Useful for asserting on identity-card and
 * is_face_down state after an ability resolves.
 */
export async function fetchPlayerDocs(page: Page, gameId: string): Promise<ServerPlayer[]> {
  return page.evaluate(async ({ gameId }) => {
    const e2e = (window as unknown as {
      __e2e?: { fetchPlayers: (gid: string) => Promise<unknown[]> };
    }).__e2e;
    if (!e2e) throw new Error('window.__e2e missing');
    return e2e.fetchPlayers(gameId);
  }, { gameId }) as Promise<ServerPlayer[]>;
}

/**
 * Poll the *server* life total for a player until it settles on `expected`.
 *
 * The board is optimistic and debounced, so the number rendered in the UI can
 * be right while the server is still behind (or, when an update is dropped,
 * right while the server is permanently wrong). Every life assertion that
 * matters therefore reads Firestore rather than the DOM.
 */
export async function expectServerLife(
  readerPage: Page,
  gameId: string,
  userId: string,
  expected: number,
  timeout = 10_000,
) {
  await expect
    .poll(
      async () => {
        const docs = await fetchPlayerDocs(readerPage, gameId);
        return docs.find((d) => d.user_id === userId)?.life_total;
      },
      { timeout, message: `server life_total for ${userId} never reached ${expected}` },
    )
    .toBe(expected);
}
