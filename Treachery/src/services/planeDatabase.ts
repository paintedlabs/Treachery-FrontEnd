import planeCards from '@/assets/PlaneCards.json';
import { PlaneCard } from '@/models/types';

const cards: PlaneCard[] = planeCards as PlaneCard[];

export function getPlane(id: string): PlaneCard | undefined {
  return cards.find((c) => c.id === id);
}

export function getAllPlanes(): PlaneCard[] {
  return cards.filter((c) => !c.is_phenomenon);
}

export function getAllCards(): PlaneCard[] {
  return cards;
}

export function getRandomPlane(excludeIds: string[] = []): PlaneCard | undefined {
  const excludeSet = new Set(excludeIds);
  const available = cards.filter((c) => !c.is_phenomenon && !excludeSet.has(c.id));
  if (available.length === 0) return undefined;
  return available[Math.floor(Math.random() * available.length)];
}
