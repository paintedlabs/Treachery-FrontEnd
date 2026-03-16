import { IdentityCard, Role } from '@/models/types';
import cardsJson from '@/assets/IdentityCards.json';

const cards: IdentityCard[] = cardsJson as IdentityCard[];
const cardById = new Map<string, IdentityCard>(cards.map((c) => [c.id, c]));

export function getAllCards(): IdentityCard[] {
  return cards;
}

export function getCard(id: string): IdentityCard | undefined {
  return cardById.get(id);
}

export function getCardsForRole(role: Role): IdentityCard[] {
  return cards.filter((c) => c.role === role);
}

export function getCardsForRarity(rarity: string): IdentityCard[] {
  return cards.filter((c) => c.rarity === rarity);
}

export function getRandomCards(role: Role, count: number): IdentityCard[] {
  const roleCards = getCardsForRole(role);
  const shuffled = [...roleCards].sort(() => Math.random() - 0.5);
  return shuffled.slice(0, count);
}
