import { Browser, Page, expect } from '@playwright/test';
import {
  GameMode,
  PlayerHandle,
  ROLE_DISTRIBUTION,
  Role,
  SeededGame,
  ServerPlayer,
  damage,
  fetchGameDoc,
  fetchPlayerDocs,
  forfeit,
  heal,
  setupNonTreacheryGame,
  setupSeededGame,
  unveilSelf,
} from '../helpers';
import { Rng } from './rng';
import { ABILITY_TRAITOR_CARDS, startingLifeFor } from './cards';
import {
  Expectations,
  InvariantViolation,
  Snapshot,
  checkInvariants,
} from './invariants';

/**
 * The fuzz loop.
 *
 * Each step: read the true server state, enumerate the moves that are legal
 * *right now*, pick one with the seeded RNG, drive it through the real UI,
 * wait for the server to settle, then re-read and assert every invariant.
 *
 * Everything random comes from {@link Rng}, so a failing run replays exactly
 * from its printed seed.
 */

export interface SimConfig {
  /** Shown in test titles and failure output. */
  label: string;
  playerCount: number;
  mode: GameMode;
  /** Upper bound on actions; the run also stops early when the game finishes. */
  maxSteps: number;
  /** Lower starting life ⇒ fewer clicks per elimination ⇒ faster runs. */
  startingLife: number;
  /** This game's RNG stream, derived from `repro.SIM_SEED`. */
  seed: number;
  /**
   * The exact environment that produced this run. Printed verbatim on failure:
   * the per-game `seed` above is *derived*, so feeding it back in as SIM_SEED
   * would replay a different game.
   */
  repro: Record<string, string | number>;
}

export interface SimResult {
  steps: number;
  finished: boolean;
  winningTeam: string | null;
  log: string[];
}

type ActionKind = 'damage' | 'heal' | 'unveil' | 'forfeit' | 'ability';

interface Candidate {
  kind: ActionKind;
  actor: PlayerHandle;
  target?: PlayerHandle;
  amount?: number;
}

/**
 * Weights are per *kind*, not per candidate — the kind is drawn first and then
 * a candidate of that kind uniformly. Weighting the flat candidate list would
 * bury unveils: an N-player game offers N² damage candidates against at most
 * N unveils, so unveils (and therefore the whole ability-resolver code path)
 * would almost never be chosen.
 *
 * Damage dominates so games actually progress toward eliminations; forfeit is
 * rare because one forfeit can end a 4-player game outright.
 */
const WEIGHTS: Record<ActionKind, number> = {
  damage: 50,
  heal: 18,
  unveil: 18,
  ability: 9,
  forfeit: 5,
};

/** Host = seat 0. Roles are laid out leader → guardians → assassins → traitors. */
function buildLayout(count: number): Role[] {
  const dist = ROLE_DISTRIBUTION[count];
  if (!dist) throw new Error(`No role distribution for ${count} players`);
  const layout: Role[] = [];
  for (let i = 0; i < dist.leader; i++) layout.push('leader');
  for (let i = 0; i < dist.guardian; i++) layout.push('guardian');
  for (let i = 0; i < dist.assassin; i++) layout.push('assassin');
  for (let i = 0; i < dist.traitor; i++) layout.push('traitor');
  return layout;
}

/**
 * Give the traitor(s) a randomly chosen *ability* card so the fuzzer actually
 * walks the Metamorph / Puppet Master / Wearer of Masks resolvers instead of
 * always drawing the first traitor in the deck.
 */
function pickCardOverrides(rng: Rng, layout: Role[]): Record<number, string> {
  const overrides: Record<number, string> = {};
  const pool = rng.shuffled(ABILITY_TRAITOR_CARDS);
  let next = 0;
  layout.forEach((role, index) => {
    if (role !== 'traitor') return;
    if (next < pool.length && rng.chance(0.8)) {
      overrides[index] = pool[next++];
    }
  });
  return overrides;
}

/**
 * Read a *consistent* snapshot of the game doc and its players.
 *
 * The elimination transaction writes `players/{id}.life_total` and
 * `games/{id}.state` together, but we read them with two separate queries, so
 * a naive read can straddle the commit and produce a game that is still
 * "in_progress" alongside players that say otherwise. Bracketing the player
 * read with two game reads and requiring the state to match rules that out.
 */
async function readSnapshot(readerPage: Page, gameId: string): Promise<Snapshot> {
  // Reads also occasionally land mid client-side navigation (a forfeiting page
  // is swapping to /game-over); the same retry loop rides that out.
  for (let attempt = 0; ; attempt++) {
    try {
      const before = await fetchGameDoc(readerPage, gameId);
      const players = await fetchPlayerDocs(readerPage, gameId);
      const after = await fetchGameDoc(readerPage, gameId);
      if (!before || !after) throw new Error(`Game ${gameId} disappeared`);
      if (before.state === after.state) return { game: after, players };
      // A transition committed while we were reading — take a fresh sample.
    } catch (error) {
      if (attempt >= 3) throw error;
      await readerPage.waitForTimeout(400);
    }
    if (attempt >= 3) throw new Error(`Game ${gameId} state kept changing mid-read`);
  }
}

function serverPlayerFor(snapshot: Snapshot, handle: PlayerHandle): ServerPlayer {
  const found = snapshot.players.find((p) => p.user_id === handle.userId);
  if (!found) throw new Error(`No player doc for ${handle.name} (${handle.userId})`);
  return found;
}

/** Poll until `predicate` holds on a fresh snapshot, or the deadline passes. */
async function settle(
  readerPage: Page,
  gameId: string,
  predicate: (s: Snapshot) => boolean,
  timeoutMs = 10_000,
): Promise<Snapshot> {
  const deadline = Date.now() + timeoutMs;
  let snapshot = await readSnapshot(readerPage, gameId);
  while (!predicate(snapshot) && Date.now() < deadline) {
    await readerPage.waitForTimeout(250);
    snapshot = await readSnapshot(readerPage, gameId);
  }
  // Deliberately no throw on timeout: an update that never lands is exactly
  // what the lifeArithmetic invariant exists to report, with better context.
  return snapshot;
}

/** True once the server says the game is over. */
async function isFinished(readerPage: Page, gameId: string): Promise<boolean> {
  try {
    return (await fetchGameDoc(readerPage, gameId))?.state === 'finished';
  } catch {
    return false;
  }
}

/**
 * Resolve (or decline) whichever traitor ability modal auto-opened after an
 * unveil. Leaving it open would block every later click on that page, so this
 * always leaves the board clickable again.
 */
async function handleAbilityModal(page: Page, cardId: string, rng: Rng, log: string[]) {
  const decline = page.getByRole('button', { name: 'Decline ability' });
  const skip = page.getByRole('button', { name: 'Skip ability' });

  if (cardId === 'traitor_07') {
    await expect(decline).toBeVisible({ timeout: 10_000 });
    const steal = page.getByRole('button', { name: /^Steal from / });
    const count = await steal.count();
    if (count > 0 && rng.chance(0.75)) {
      await steal.nth(rng.int(0, count - 1)).click();
      await page.getByRole('button', { name: 'Steal identity' }).click();
      log.push('    ability: Metamorph stole an eliminated identity');
    } else {
      await decline.click();
      log.push('    ability: Metamorph declined');
    }
  } else if (cardId === 'traitor_09') {
    await expect(decline).toBeVisible({ timeout: 10_000 });
    const swap = page.getByRole('button', { name: /^Swap with / });
    const count = await swap.count();
    if (count >= 2 && rng.chance(0.75)) {
      const [a, b] = rng.shuffled([...Array(count).keys()]).slice(0, 2);
      await swap.nth(a).click();
      await swap.nth(b).click();
      await page.getByRole('button', { name: 'Confirm redistribution' }).click();
      log.push('    ability: Puppet Master swapped two identities');
    } else {
      await decline.click();
      log.push('    ability: Puppet Master declined');
    }
  } else if (cardId === 'traitor_13') {
    await expect(skip).toBeVisible({ timeout: 10_000 });
    if (rng.chance(0.75)) {
      await page.getByRole('button', { name: 'Reveal cards' }).click();
      const picks = page.getByRole('button', { name: /^Pick identity / });
      await expect(picks.first()).toBeVisible({ timeout: 10_000 });
      const count = await picks.count();
      await picks.nth(rng.int(0, count - 1)).click();
      await page.getByRole('button', { name: 'Become this identity' }).click();
      log.push('    ability: Wearer of Masks copied a card');
    } else {
      await skip.click();
      log.push('    ability: Wearer of Masks skipped');
    }
  }

  // The sheet closes on resolve/decline; make sure nothing is left covering
  // the board before the next step tries to click a life button.
  await expect(decline.or(skip)).toBeHidden({ timeout: 10_000 });
}

/** Every move that is legal against the current server state, grouped by kind. */
function legalMoves(
  game: SeededGame,
  snapshot: Snapshot,
  rng: Rng,
  treachery: boolean,
): Map<ActionKind, Candidate[]> {
  const alive = game.players.filter((h) => !serverPlayerFor(snapshot, h).is_eliminated);
  const byKind = new Map<ActionKind, Candidate[]>();
  const add = (c: Candidate) => {
    const list = byKind.get(c.kind);
    if (list) list.push(c);
    else byKind.set(c.kind, [c]);
  };

  for (const actor of alive) {
    const actorDoc = serverPlayerFor(snapshot, actor);

    for (const target of alive) {
      const life = serverPlayerFor(snapshot, target).life_total ?? 0;
      if (life <= 0) continue;

      // Sometimes swing for the kill; usually chip away without eliminating.
      const lethal = rng.chance(0.15);
      const amount = lethal || life === 1 ? life : Math.min(life - 1, rng.int(1, 3));
      if (amount > 0) add({ kind: 'damage', actor, target, amount });
      add({ kind: 'heal', actor, target, amount: rng.int(1, 3) });
    }

    if (treachery) {
      const cardId = actorDoc.identity_card_id ?? '';
      const hasResolver = (ABILITY_TRAITOR_CARDS as readonly string[]).includes(cardId);

      // unveilPlayer rejects leaders (always visible) and anyone already unveiled.
      if (!actorDoc.is_unveiled && actorDoc.role !== 'leader') {
        add({ kind: 'unveil', actor });
        // Importance sampling: unveiling one of the three resolver traitors is
        // the only way into the Metamorph / Puppet Master / Wearer of Masks
        // code paths, and a uniform pick reaches them roughly once per twenty
        // unveils. Weighting them up keeps a short CI run meaningful without
        // making any illegal move reachable.
        if (hasResolver) {
          add({ kind: 'unveil', actor });
          add({ kind: 'unveil', actor });
          add({ kind: 'unveil', actor });
        }
      }

      // The resolver sheet auto-opens once at unveil, but the board keeps an
      // "Activate Ability" button for as long as the player still holds the
      // card. That re-entry matters: the Metamorph has nothing to steal until
      // somebody has been eliminated, which is usually long after it unveiled.
      if (actorDoc.is_unveiled && hasResolver) {
        add({ kind: 'ability', actor });
      }

      add({ kind: 'forfeit', actor });
    }
  }

  return byKind;
}

/** Draw a kind by weight, then a candidate of that kind uniformly. */
function chooseMove(byKind: Map<ActionKind, Candidate[]>, rng: Rng): Candidate | null {
  const kinds = [...byKind.entries()]
    .filter(([, list]) => list.length > 0)
    .map(([kind]) => ({ value: kind, weight: WEIGHTS[kind] }));
  if (kinds.length === 0) return null;
  return rng.pick(byKind.get(rng.pickWeighted(kinds))!);
}

export async function runSimulation(browser: Browser, config: SimConfig): Promise<SimResult> {
  const rng = new Rng(config.seed);
  const treachery = config.mode === 'treachery' || config.mode === 'treachery_planechase';
  const log: string[] = [
    `sim "${config.label}": seed=${config.seed} players=${config.playerCount} mode=${config.mode} startingLife=${config.startingLife}`,
  ];

  let game: SeededGame;
  if (treachery) {
    const layout = buildLayout(config.playerCount);
    const cardOverrides = pickCardOverrides(rng, layout);
    log.push(`  seeded roles: ${layout.join(', ')}; overrides: ${JSON.stringify(cardOverrides)}`);
    game = await setupSeededGame(browser, layout, {
      cardOverrides,
      startingLife: config.startingLife,
    });
  } else {
    game = await setupNonTreacheryGame(
      browser,
      config.playerCount,
      config.mode as 'planechase' | 'none',
      { startingLife: config.startingLife },
    );
  }

  const readerPage = game.players[0].page;
  const expectations: Expectations = {
    mode: config.mode,
    life: new Map(),
    eliminated: new Set(),
    unveiled: new Set(),
  };

  let snapshot = await readSnapshot(readerPage, game.gameId);

  // Seed the life model from the *computed* expectation, not from the server,
  // so a wrong starting life (e.g. a missed card life_modifier) fails here.
  for (const handle of game.players) {
    const doc = serverPlayerFor(snapshot, handle);
    const expectedStart = startingLifeFor(config.startingLife, doc.identity_card_id);
    if ((doc.life_total ?? 0) !== expectedStart) {
      throw new InvariantViolation(
        'startingLife',
        `${handle.name} started at ${doc.life_total} life; ` +
          `game starting_life ${config.startingLife} + card modifier implies ${expectedStart}`,
      );
    }
    expectations.life.set(handle.userId, expectedStart);
  }

  let previous: Snapshot | null = null;
  checkInvariants(previous, snapshot, expectations, false);

  /**
   * Drive one move through the UI and wait for the server to catch up.
   * Updates `expectations` with what the move should have done.
   */
  const applyMove = async (
    move: Candidate,
    step: number,
    current: Snapshot,
  ): Promise<{ snapshot: Snapshot; lifeChange: boolean }> => {
    switch (move.kind) {
      case 'damage':
      case 'heal': {
        const target = move.target!;
        const amount = move.amount!;
        const signed = move.kind === 'damage' ? -amount : amount;
        const before = expectations.life.get(target.userId)!;
        const after = Math.max(0, before + signed);
        log.push(
          `  ${step}. ${move.actor.name} ${move.kind === 'damage' ? '-' : '+'}${amount} → ${target.name} (${before}→${after})`,
        );

        if (move.kind === 'damage') {
          await damage(move.actor.page, target.name, amount);
        } else {
          await heal(move.actor.page, target.name, amount);
        }
        expectations.life.set(target.userId, after);
        if (after === 0) {
          expectations.eliminated.add(target.userId);
          expectations.unveiled.add(target.userId);
        }
        return {
          lifeChange: true,
          snapshot: await settle(
            readerPage,
            game.gameId,
            (s) => (serverPlayerFor(s, target).life_total ?? -1) === after,
          ),
        };
      }

      case 'unveil': {
        const actorDoc = serverPlayerFor(current, move.actor);
        log.push(`  ${step}. ${move.actor.name} unveils (${actorDoc.identity_card_id})`);
        await unveilSelf(move.actor.page);
        expectations.unveiled.add(move.actor.userId);
        let next = await settle(
          readerPage,
          game.gameId,
          (s) => serverPlayerFor(s, move.actor).is_unveiled === true,
        );
        const cardId = actorDoc.identity_card_id;
        if (cardId && (ABILITY_TRAITOR_CARDS as readonly string[]).includes(cardId)) {
          await handleAbilityModal(move.actor.page, cardId, rng, log);
          // The resolvers move cards and roles around; re-read before asserting.
          next = await readSnapshot(readerPage, game.gameId);
        }
        return { lifeChange: false, snapshot: next };
      }

      case 'ability': {
        const actorDoc = serverPlayerFor(current, move.actor);
        const cardId = actorDoc.identity_card_id!;
        log.push(`  ${step}. ${move.actor.name} re-activates ${cardId}`);
        await move.actor.page.getByRole('button', { name: 'Activate ability' }).click();
        await handleAbilityModal(move.actor.page, cardId, rng, log);
        return { lifeChange: false, snapshot: await readSnapshot(readerPage, game.gameId) };
      }

      case 'forfeit': {
        log.push(`  ${step}. ${move.actor.name} forfeits`);
        await forfeit(move.actor.page);
        expectations.life.set(move.actor.userId, 0);
        expectations.eliminated.add(move.actor.userId);
        expectations.unveiled.add(move.actor.userId);
        return {
          lifeChange: false,
          snapshot: await settle(
            readerPage,
            game.gameId,
            (s) => serverPlayerFor(s, move.actor).is_eliminated === true,
          ),
        };
      }
    }
  };

  let steps = 0;
  try {
    for (; steps < config.maxSteps; steps++) {
      if (snapshot.game.state !== 'in_progress') break;

      const move = chooseMove(legalMoves(game, snapshot, rng, treachery), rng);
      if (!move) break;

      previous = snapshot;
      let lifeChange = false;
      let ranOut = false;

      try {
        const outcome = await applyMove(move, steps, snapshot);
        snapshot = outcome.snapshot;
        lifeChange = outcome.lifeChange;
      } catch (error) {
        // The board unmounts the moment the game ends, so the tail of a
        // multi-tap burst can land on a page that is already navigating to
        // /game-over. That is the app behaving correctly — confirm with the
        // server and stop the run rather than reporting a dead locator.
        if (!(await isFinished(readerPage, game.gameId))) throw error;
        log.push('    (game ended mid-action; board unmounted)');
        snapshot = await readSnapshot(readerPage, game.gameId);
        lifeChange = move.kind === 'damage' || move.kind === 'heal';
        ranOut = true;
      }

      checkInvariants(previous, snapshot, expectations, lifeChange);
      if (ranOut) {
        steps++;
        break;
      }
    }
  } catch (error) {
    // Re-throw with the whole replay attached — the seed alone reproduces it,
    // but the move list says what happened without re-running anything.
    const detail = error instanceof Error ? error.message : String(error);
    const env = Object.entries(config.repro)
      .map(([k, v]) => `${k}=${v}`)
      .join(' ');
    throw new Error(
      `Simulation "${config.label}" failed at step ${steps}.\n` +
        `Reproduce with: ${env} npm run test:e2e -- simulation\n` +
        `(this game's derived RNG stream: ${config.seed})\n\n` +
        `${detail}\n\nMoves:\n${log.join('\n')}`,
    );
  }

  log.push(
    `  done after ${steps} step(s); state=${snapshot.game.state} winning_team=${snapshot.game.winning_team ?? 'none'}`,
  );

  return {
    steps,
    finished: snapshot.game.state === 'finished',
    winningTeam: (snapshot.game.winning_team as string | null) ?? null,
    log,
  };
}
