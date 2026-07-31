/**
 * Deterministic RNG for the fuzz harness.
 *
 * Every random choice the simulation makes — which player acts, what they do,
 * how hard they hit — comes from here, so a failing run is reproducible from
 * its seed alone (`SIM_SEED=... npm run test:e2e`). Math.random() must never
 * be used inside e2e/simulation for that reason.
 */

/** mulberry32 — small, fast, good enough for choosing moves. */
export class Rng {
  private state: number;

  constructor(readonly seed: number) {
    // Force to uint32 so the same seed produces the same stream everywhere.
    this.state = seed >>> 0;
  }

  /** Uniform float in [0, 1). */
  next(): number {
    this.state = (this.state + 0x6d2b79f5) >>> 0;
    let t = this.state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }

  /** Uniform integer in [min, max] inclusive. */
  int(min: number, max: number): number {
    if (max < min) throw new Error(`Rng.int: max (${max}) < min (${min})`);
    return min + Math.floor(this.next() * (max - min + 1));
  }

  /** True with probability `p`. */
  chance(p: number): boolean {
    return this.next() < p;
  }

  /** Uniform element of a non-empty array. */
  pick<T>(items: readonly T[]): T {
    if (items.length === 0) throw new Error('Rng.pick: empty array');
    return items[this.int(0, items.length - 1)];
  }

  /** Weighted pick. Entries with weight <= 0 are never chosen. */
  pickWeighted<T>(entries: readonly { value: T; weight: number }[]): T {
    const usable = entries.filter((e) => e.weight > 0);
    if (usable.length === 0) throw new Error('Rng.pickWeighted: no entry with positive weight');
    const total = usable.reduce((sum, e) => sum + e.weight, 0);
    let roll = this.next() * total;
    for (const entry of usable) {
      roll -= entry.weight;
      if (roll <= 0) return entry.value;
    }
    return usable[usable.length - 1].value;
  }

  /** Fisher-Yates copy, driven by this stream. */
  shuffled<T>(items: readonly T[]): T[] {
    const arr = [...items];
    for (let i = arr.length - 1; i > 0; i--) {
      const j = this.int(0, i);
      [arr[i], arr[j]] = [arr[j], arr[i]];
    }
    return arr;
  }
}

/**
 * Resolve the run's seed. CI pins a constant so the suite is reproducible
 * build to build; locally, `SIM_SEED=random` (or any integer) re-rolls it.
 */
export function resolveSeed(fallback: number): number {
  const raw = process.env.SIM_SEED;
  if (!raw) return fallback;
  if (raw === 'random') {
    const rolled = Math.floor(Math.random() * 0xffffffff);
    // Pin it back into the environment so worker processes, which re-import
    // this file, roll the *same* seed as the process that collected the tests.
    process.env.SIM_SEED = String(rolled);
    return rolled;
  }
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed)) {
    throw new Error(`SIM_SEED must be an integer or "random" (got ${JSON.stringify(raw)})`);
  }
  return parsed >>> 0;
}
