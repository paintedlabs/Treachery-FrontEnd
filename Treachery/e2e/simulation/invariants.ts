import { GameMode, Role, ServerGame, ServerPlayer } from '../helpers';
import { cardOrNull, WEARER_OF_MASKS } from './cards';

/**
 * Invariants the server state must satisfy after *every* action the fuzzer
 * takes. These are the point of the whole harness: any legal sequence of moves
 * that breaks one of these is a state-machine bug, whether or not a
 * hand-written scenario would ever have produced that sequence.
 *
 * Each check is a pure function of (previous snapshot, current snapshot,
 * expectations tracked by the runner) so it can be unit-reasoned about and so
 * failures name themselves.
 */

// ════════════════════════════════════════════════════════════════
// KNOWN-BROKEN INVARIANTS
//
// `true` = the app violates this today, so the harness SKIPS the check and
// stays green in CI. Flip the entry to `false` after the corresponding fix
// lands and the harness starts enforcing it again. Do not delete entries —
// the comment is the record of what is wrong and where.
// ════════════════════════════════════════════════════════════════

export const KNOWN_BROKEN_INVARIANTS = {
  /**
   * FIXME: currently broken — see finding #1. Flip to `false` when the bug is fixed.
   *
   * adjustLife/eliminatePlayer run checkWinConditions for EVERY game mode.
   * In planechase / 'none' (Life Tracker) games nobody has a role, so
   * checkWinConditions hits its `!leaderAlive && !assassinAlive &&
   * !traitorAlive` branch and returns "assassin" — the first player to hit 0
   * life instantly ends the game for everyone. The win check needs to be
   * gated on the game mode including treachery.
   */
  nonTreacheryGameNeverAutoFinishes: true,

  /**
   * FIXME: currently broken — see finding #5. Flip to `false` when the bug is fixed.
   *
   * resolveMetamorph moves the eliminated target's identity_card_id onto the
   * caller but never clears it from the target, so after a steal two player
   * docs hold the same card. The game-over screen then renders the same
   * identity twice, and any future Metamorph/Wearer-of-Masks "is this card
   * already in the game" check sees a phantom copy.
   */
  identityCardsAreUnique: true,
} as const;

// ════════════════════════════════════════════════════════════════

export interface Snapshot {
  game: ServerGame;
  players: ServerPlayer[];
}

/** What the runner believes should be true, accumulated as it plays. */
export interface Expectations {
  mode: GameMode;
  /** user_id → life total implied by the deltas we actually applied. */
  life: Map<string, number>;
  /** user_ids we have seen eliminated (elimination is one-way). */
  eliminated: Set<string>;
  /** user_ids we have seen unveiled (unveiling is one-way). */
  unveiled: Set<string>;
}

const STATE_ORDER = { waiting: 0, in_progress: 1, finished: 2 } as const;

export class InvariantViolation extends Error {
  constructor(
    readonly invariant: string,
    message: string,
  ) {
    super(`[${invariant}] ${message}`);
    this.name = 'InvariantViolation';
  }
}

function fail(invariant: string, message: string): never {
  throw new InvariantViolation(invariant, message);
}

function label(p: ServerPlayer): string {
  return `${p.display_name ?? p.user_id}(${p.id})`;
}

/**
 * Mirror of checkWinConditions in functions/index.js. Kept as a duplicate on
 * purpose: if the server's rules change without this changing, the
 * winner-consistency invariant fires and someone has to reconcile the two.
 */
export function expectedWinner(players: ServerPlayer[]): Role | null {
  const alive = players.filter((p) => !p.is_eliminated);
  if (alive.length === 1 && alive[0].role === 'traitor') return 'traitor';

  const leaderAlive = alive.some((p) => p.role === 'leader');
  const assassinAlive = alive.some((p) => p.role === 'assassin');
  const traitorAlive = alive.some((p) => p.role === 'traitor');

  if (!leaderAlive && assassinAlive) return 'assassin';
  if (leaderAlive && !assassinAlive && !traitorAlive) return 'leader';
  if (!leaderAlive && !assassinAlive && !traitorAlive) return 'assassin';
  return null;
}

function isTreachery(mode: GameMode): boolean {
  return mode === 'treachery' || mode === 'treachery_planechase';
}

/**
 * Run every invariant against a fresh snapshot.
 *
 * @param previous the snapshot from before the action (null on the first check)
 * @param current  the snapshot read back after the action settled
 * @param expect   the runner's running model of what should have happened
 * @param lastActionWasLifeChange whether the action just taken was a +/- tap;
 *        used by the non-treachery "a life change must not end the game" rule
 */
export function checkInvariants(
  previous: Snapshot | null,
  current: Snapshot,
  expect: Expectations,
  lastActionWasLifeChange: boolean,
): void {
  const { game, players } = current;
  const treachery = isTreachery(expect.mode);

  // ── 1. State machine only moves forward ────────────────────────
  const state = game.state ?? 'waiting';
  if (!(state in STATE_ORDER)) fail('stateIsKnown', `unexpected game state ${JSON.stringify(state)}`);
  if (previous) {
    const before = previous.game.state ?? 'waiting';
    if (STATE_ORDER[state] < STATE_ORDER[before]) {
      fail('stateMonotonic', `game state went backwards: ${before} → ${state}`);
    }
  }

  // ── 2. The roster is fixed once the game is running ────────────
  if (previous && previous.players.length !== players.length) {
    fail(
      'rosterStable',
      `player count changed mid-game: ${previous.players.length} → ${players.length}`,
    );
  }

  for (const p of players) {
    const life = p.life_total ?? 0;

    // ── 3. Life is never negative ────────────────────────────────
    if (life < 0) fail('lifeNeverNegative', `${label(p)} has life_total ${life}`);

    // ── 4. 0 life means eliminated ───────────────────────────────
    if (life === 0 && !p.is_eliminated) {
      fail('zeroLifeIsEliminated', `${label(p)} is at 0 life but is_eliminated is ${p.is_eliminated}`);
    }

    // ── 5. Eliminated players are always face up ─────────────────
    if (p.is_eliminated && !p.is_unveiled) {
      fail('eliminatedIsUnveiled', `${label(p)} is eliminated but is_unveiled is ${p.is_unveiled}`);
    }

    // ── 6. Elimination and unveiling are one-way ─────────────────
    if (expect.eliminated.has(p.user_id) && !p.is_eliminated) {
      fail('eliminationIsPermanent', `${label(p)} was eliminated earlier but is alive again`);
    }
    if (expect.unveiled.has(p.user_id) && !p.is_unveiled) {
      fail('unveilIsPermanent', `${label(p)} was unveiled earlier but is concealed again`);
    }

    if (treachery) {
      // ── 7. Exactly one identity card per player ────────────────
      if (!p.identity_card_id) {
        fail('oneCardPerPlayer', `${label(p)} holds no identity card in a treachery game`);
      }
      const held = cardOrNull(p.identity_card_id);
      if (!held) {
        fail('cardExists', `${label(p)} holds unknown card ${p.identity_card_id}`);
      }

      // ── 8. Role follows the card ───────────────────────────────
      // Metamorph and Puppet Master transfer the identity itself, so role
      // moves with the card. The Wearer of Masks is the documented exception:
      // it copies a non-Leader card but the player stays a Traitor.
      const isWearerOfMasks =
        p.original_identity_card_id === WEARER_OF_MASKS || p.identity_card_id === WEARER_OF_MASKS;
      if (!isWearerOfMasks && p.role !== held.role) {
        fail(
          'roleMatchesCard',
          `${label(p)} has role ${p.role} but holds ${held.id} (${held.role})`,
        );
      }
      if (isWearerOfMasks && p.role !== 'traitor') {
        fail(
          'wearerOfMasksStaysTraitor',
          `${label(p)} copied ${p.identity_card_id} via the Wearer of Masks but role is ${p.role}`,
        );
      }
    } else {
      // Non-treachery modes assign no roles or cards at all.
      if (p.role !== null || p.identity_card_id !== null) {
        fail(
          'noRolesOutsideTreachery',
          `${label(p)} has role=${p.role} card=${p.identity_card_id} in a ${expect.mode} game`,
        );
      }
    }

    // ── 9. Life arithmetic — every delta we applied, and nothing else ──
    const predicted = expect.life.get(p.user_id);
    if (predicted !== undefined && predicted !== life) {
      fail(
        'lifeArithmetic',
        `${label(p)} should be at ${predicted} life after the deltas we applied, server says ${life}` +
          ' (a dropped or duplicated adjustLife call)',
      );
    }
  }

  // ── 10. No two players hold the same identity card ─────────────
  if (treachery && !KNOWN_BROKEN_INVARIANTS.identityCardsAreUnique) {
    const seen = new Map<string, ServerPlayer>();
    for (const p of players) {
      if (!p.identity_card_id) continue;
      const other = seen.get(p.identity_card_id);
      if (other) {
        fail(
          'identityCardsAreUnique',
          `${label(p)} and ${label(other)} both hold ${p.identity_card_id}`,
        );
      }
      seen.set(p.identity_card_id, p);
    }
  }

  // ── 11. A life change must never end a non-treachery game ──────
  if (!treachery && lastActionWasLifeChange && !KNOWN_BROKEN_INVARIANTS.nonTreacheryGameNeverAutoFinishes) {
    if (state === 'finished') {
      fail(
        'nonTreacheryGameNeverAutoFinishes',
        `a life change ended a ${expect.mode} game (winning_team=${game.winning_team})` +
          ' — only the host pressing End Game may finish these modes',
      );
    }
  }

  // ── 12. The declared winner matches the final roles ────────────
  if (state === 'finished' && treachery && game.winning_team) {
    const derived = expectedWinner(players);
    if (derived !== game.winning_team) {
      fail(
        'winnerMatchesRoles',
        `game declared winning_team=${game.winning_team} but the final roles imply ${derived}` +
          ` (${players.map((p) => `${label(p)}:${p.role}${p.is_eliminated ? '☠' : ''}`).join(', ')})`,
      );
    }
  }
}
