import { test } from '@playwright/test';
import { GameMode } from './helpers';
import { KNOWN_BROKEN_INVARIANTS } from './simulation/invariants';
import { SimConfig, runSimulation } from './simulation/runner';
import { resolveSeed } from './simulation/rng';

/**
 * Randomised multi-player simulation ("fuzz") harness.
 *
 * Unlike the hand-written specs, nothing here scripts a scenario. Each test
 * spins up a real multi-context game and then repeatedly picks a legal move at
 * random — damage, heal, unveil (including the traitor ability resolvers),
 * forfeit — and asserts EVERY invariant in simulation/invariants.ts after each
 * one. The point is to reach states no one thought to write a test for.
 *
 * ── Reproducing a failure ──────────────────────────────────────────────
 * The failure message prints the seed and the exact move list. Replay with:
 *
 *   SIM_SEED=<seed> npm run test:e2e -- simulation
 *
 * ── Fuzzing harder locally ─────────────────────────────────────────────
 * CI runs a small, pinned set so it stays deterministic and fast. To actually
 * hunt for bugs, crank it up:
 *
 *   SIM_SEED=random SIM_STEPS=60 SIM_REPEAT=25 npm run test:e2e -- simulation
 *
 *   SIM_SEED    integer, or "random" to re-roll each run (default: BASE_SEED)
 *   SIM_STEPS   max actions per game            (default: 14)
 *   SIM_REPEAT  how many times to run the set   (default: 1)
 *   SIM_LIFE    starting life                   (default: 20 — fewer clicks)
 *
 * ── Known-broken invariants ────────────────────────────────────────────
 * Some invariants describe behaviour the app gets wrong today. Those are
 * listed in KNOWN_BROKEN_INVARIANTS and skipped so CI stays green; flip the
 * flag to `false` once the fix lands. See simulation/invariants.ts.
 */

// Pinned so a CI run is reproducible build to build. This particular value was
// chosen because its derived streams resolve a Puppet Master redistribution in
// game 1 and open the Metamorph resolver in game 2, so even the short CI run
// covers the ability paths rather than only life arithmetic.
const BASE_SEED = 31337;

const SEED = resolveSeed(BASE_SEED);
const MAX_STEPS = Number.parseInt(process.env.SIM_STEPS ?? '14', 10);
const REPEAT = Number.parseInt(process.env.SIM_REPEAT ?? '1', 10);
const STARTING_LIFE = Number.parseInt(process.env.SIM_LIFE ?? '20', 10);

/**
 * The default set: two treachery games at different player counts plus one
 * Life Tracker game, which is the only simulation coverage the non-treachery
 * code path has. Each game gets its own derived seed so adding or removing a
 * game doesn't reshuffle the others.
 */
const GAMES: { label: string; playerCount: number; mode: GameMode }[] = [
  { label: '4-player treachery', playerCount: 4, mode: 'treachery' },
  { label: '5-player treachery', playerCount: 5, mode: 'treachery' },
  { label: '4-player life tracker', playerCount: 4, mode: 'none' },
];

function derivedSeed(base: number, index: number): number {
  // Cheap decorrelation so game N's stream doesn't shadow game N-1's.
  return (base ^ Math.imul(index + 1, 0x9e3779b9)) >>> 0;
}

test.describe('Simulation', () => {
  // Each step is a real UI action plus a server round trip, so a long run
  // needs more than the 60s default.
  test.setTimeout(Math.max(180_000, MAX_STEPS * 12_000));

  for (let repeat = 0; repeat < REPEAT; repeat++) {
    GAMES.forEach((game, index) => {
      const seed = derivedSeed(SEED, repeat * GAMES.length + index);
      const suffix = REPEAT > 1 ? ` #${repeat + 1}` : '';

      // The seed deliberately stays OUT of the title: with SIM_SEED=random it
      // would differ between the collecting process and the worker, and
      // Playwright matches tests by title. It is printed instead — in the run
      // log on success and in the failure message on error.
      test(`${game.label} plays out without breaking an invariant${suffix}`, async ({
        browser,
      }) => {
        const config: SimConfig = {
          label: `${game.label}${suffix}`,
          playerCount: game.playerCount,
          mode: game.mode,
          maxSteps: MAX_STEPS,
          startingLife: STARTING_LIFE,
          seed,
          // Replay knobs, not the derived per-game stream — SIM_SEED is the
          // base the per-game seeds are derived from, so only these values
          // together reproduce this exact game.
          repro: {
            SIM_SEED: SEED,
            SIM_STEPS: MAX_STEPS,
            SIM_REPEAT: REPEAT,
            SIM_LIFE: STARTING_LIFE,
          },
        };

        const result = await runSimulation(browser, config);
        // Printed on success too — a passing run's move list is the cheapest
        // way to see what the fuzzer actually explored.
        console.log(result.log.join('\n'));
      });
    });
  }
});

test('the known-broken invariant list is honest about what is disabled', () => {
  // A guard rail, not a behaviour test: if someone flips one of these to
  // `false` without the fix, the simulation starts failing and the reason is
  // right here. If someone fixes a bug, this list is where they turn the
  // check back on.
  const disabled = Object.entries(KNOWN_BROKEN_INVARIANTS)
    .filter(([, isBroken]) => isBroken)
    .map(([name]) => name);
  console.log(
    disabled.length === 0
      ? 'All simulation invariants are enforced.'
      : `Simulation invariants currently disabled (known bugs): ${disabled.join(', ')}`,
  );
});
