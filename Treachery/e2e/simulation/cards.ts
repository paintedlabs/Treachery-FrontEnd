import fs from 'fs';
import path from 'path';
import { Role } from '../helpers';

/**
 * Identity card metadata, read straight off the copy the Cloud Functions use.
 *
 * The invariants need to know a card's role (to assert `player.role` still
 * matches the card it holds) and its life modifier (to predict starting life).
 * Reading functions/identityCards.json rather than re-declaring the data here
 * means the harness can never drift from the server's view of the deck.
 */

export interface CardMeta {
  id: string;
  name: string;
  role: Role;
  rarity: string;
  life_modifier: number | null;
}

const CARDS_PATH = path.resolve(__dirname, '../../../functions/identityCards.json');

export const ALL_CARDS: CardMeta[] = JSON.parse(fs.readFileSync(CARDS_PATH, 'utf8'));

const BY_ID = new Map(ALL_CARDS.map((c) => [c.id, c]));

export function card(id: string): CardMeta {
  const found = BY_ID.get(id);
  if (!found) throw new Error(`Unknown identity card id: ${id}`);
  return found;
}

export function cardOrNull(id: string | null | undefined): CardMeta | null {
  if (!id) return null;
  return BY_ID.get(id) ?? null;
}

/** Life a player starts with, given the game's starting_life and their card. */
export function startingLifeFor(gameStartingLife: number, cardId: string | null): number {
  return gameStartingLife + (cardOrNull(cardId)?.life_modifier ?? 0);
}

// The three traitor identities with a follow-up resolver modal. The simulation
// deliberately seeds these so the fuzzer walks the ability code paths that the
// hand-written abilities.spec.ts only visits one at a time.
export const METAMORPH = 'traitor_07';
export const PUPPET_MASTER = 'traitor_09';
export const WEARER_OF_MASKS = 'traitor_13';
export const ABILITY_TRAITOR_CARDS = [METAMORPH, PUPPET_MASTER, WEARER_OF_MASKS] as const;
