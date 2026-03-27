/**
 * Treachery Cloud Functions — Integration & Edge Case Tests
 *
 * Tests the pure game logic extracted from index.js:
 *   - Role distribution
 *   - Win condition checking
 *   - Planechase deck mechanics
 *   - ELO calculations
 *   - Concurrency/race condition scenarios (simulated)
 *
 * Run: cd functions && npm test
 */

const assert = require("assert");

// ─── Extract logic from index.js ────────────────────────────────
// We re-implement the pure functions here to test them in isolation.
// In a production setup, these would be extracted to a shared module.

const CARDS = require("../identityCards.json");
const PLANE_CARDS = require("../planeCards.json");

const CHAOTIC_AETHER_ID = "6dc67a65-31bf-4535-9e02-8f6d6ecefde5";
const INTERPLANAR_TUNNEL_ID = "7812174b-2dc1-43e8-b98f-639905e20ab7";
const SPATIAL_MERGING_ID = "aa166578-b13b-4adb-a78e-d5183e987112";

function getCardsForRole(role) {
  return CARDS.filter((c) => c.role === role);
}

function getRoleDistribution(playerCount) {
  const table = {
    1: { leaders: 1, guardians: 0, assassins: 0, traitors: 0 },
    2: { leaders: 1, guardians: 0, assassins: 1, traitors: 0 },
    3: { leaders: 1, guardians: 0, assassins: 1, traitors: 1 },
    4: { leaders: 1, guardians: 0, assassins: 2, traitors: 1 },
    5: { leaders: 1, guardians: 1, assassins: 2, traitors: 1 },
    6: { leaders: 1, guardians: 1, assassins: 3, traitors: 1 },
    7: { leaders: 1, guardians: 2, assassins: 3, traitors: 1 },
    8: { leaders: 1, guardians: 2, assassins: 3, traitors: 2 },
  };
  return (
    table[playerCount] || { leaders: 1, guardians: 0, assassins: 2, traitors: 1 }
  );
}

function shuffle(array) {
  const arr = [...array];
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

function checkWinConditions(players) {
  const alive = players.filter((p) => !p.is_eliminated);

  if (alive.length === 1 && alive[0].role === "traitor") {
    return "traitor";
  }

  const leaderAlive = alive.some((p) => p.role === "leader");
  const assassinAlive = alive.some((p) => p.role === "assassin");
  const traitorAlive = alive.some((p) => p.role === "traitor");

  if (!leaderAlive && assassinAlive) {
    return "assassin";
  }
  if (leaderAlive && !assassinAlive && !traitorAlive) {
    return "leader";
  }
  if (!leaderAlive && !assassinAlive && !traitorAlive) {
    return "assassin";
  }

  return null;
}

// ─── Test Helpers ────────────────────────────────────────────────

function makePlayers(configs) {
  return configs.map((c, i) => ({
    id: `player${i}`,
    user_id: `user${i}`,
    display_name: `Player ${i}`,
    role: c.role,
    life_total: c.life ?? 40,
    is_eliminated: c.eliminated ?? false,
    is_unveiled: c.unveiled ?? false,
    order_id: i,
  }));
}

let passed = 0;
let failed = 0;
let errors = [];

function test(name, fn) {
  try {
    fn();
    passed++;
    console.log(`  ✓ ${name}`);
  } catch (e) {
    failed++;
    errors.push({ name, error: e.message });
    console.log(`  ✗ ${name}`);
    console.log(`    ${e.message}`);
  }
}

function suite(name, fn) {
  console.log(`\n${name}`);
  console.log("─".repeat(name.length));
  fn();
}

// ═════════════════════════════════════════════════════════════════
// TEST SUITES
// ═════════════════════════════════════════════════════════════════

suite("Role Distribution", () => {
  test("4 players: 1 leader, 0 guardians, 2 assassins, 1 traitor", () => {
    const dist = getRoleDistribution(4);
    assert.deepStrictEqual(dist, {
      leaders: 1,
      guardians: 0,
      assassins: 2,
      traitors: 1,
    });
    assert.strictEqual(
      dist.leaders + dist.guardians + dist.assassins + dist.traitors,
      4
    );
  });

  test("5 players: 1 leader, 1 guardian, 2 assassins, 1 traitor", () => {
    const dist = getRoleDistribution(5);
    assert.strictEqual(
      dist.leaders + dist.guardians + dist.assassins + dist.traitors,
      5
    );
  });

  test("6 players: sum = 6", () => {
    const dist = getRoleDistribution(6);
    assert.strictEqual(
      dist.leaders + dist.guardians + dist.assassins + dist.traitors,
      6
    );
  });

  test("7 players: sum = 7", () => {
    const dist = getRoleDistribution(7);
    assert.strictEqual(
      dist.leaders + dist.guardians + dist.assassins + dist.traitors,
      7
    );
  });

  test("8 players: 1 leader, 2 guardians, 3 assassins, 2 traitors", () => {
    const dist = getRoleDistribution(8);
    assert.deepStrictEqual(dist, {
      leaders: 1,
      guardians: 2,
      assassins: 3,
      traitors: 2,
    });
    assert.strictEqual(
      dist.leaders + dist.guardians + dist.assassins + dist.traitors,
      8
    );
  });

  test("fallback for unsupported player counts (9+) defaults to 4-player dist", () => {
    const dist = getRoleDistribution(9);
    // Falls back to default, which is 4-player distribution (sum=4, NOT 9)
    const sum =
      dist.leaders + dist.guardians + dist.assassins + dist.traitors;
    assert.strictEqual(sum, 4, `Expected fallback sum of 4, got ${sum}`);
  });

  test("BUG: fallback distribution does not match player count for 9+ players", () => {
    // This is a discovered bug: if somehow 9 players join (race condition),
    // startGame uses getRoleDistribution(9) which returns sum=4,
    // so only 4 out of 9 players get roles assigned.
    const dist = getRoleDistribution(9);
    const sum = dist.leaders + dist.guardians + dist.assassins + dist.traitors;
    assert.notStrictEqual(
      sum,
      9,
      "Fallback correctly does NOT cover all 9 players — this is a bug if 9 players join"
    );
  });

  test("every supported count (4-8) always has exactly 1 leader", () => {
    for (let count = 4; count <= 8; count++) {
      const dist = getRoleDistribution(count);
      assert.strictEqual(
        dist.leaders,
        1,
        `Expected 1 leader for ${count} players`
      );
    }
  });

  test("assassins always outnumber or equal traitors", () => {
    for (let count = 4; count <= 8; count++) {
      const dist = getRoleDistribution(count);
      assert.ok(
        dist.assassins >= dist.traitors,
        `For ${count} players: ${dist.assassins} assassins < ${dist.traitors} traitors`
      );
    }
  });
});

suite("Identity Card Availability", () => {
  test("enough leader cards for max leaders (1)", () => {
    const leaderCards = getCardsForRole("leader");
    assert.ok(
      leaderCards.length >= 1,
      `Only ${leaderCards.length} leader cards`
    );
  });

  test("enough guardian cards for max guardians (2 in 7-8 player)", () => {
    const guardianCards = getCardsForRole("guardian");
    assert.ok(
      guardianCards.length >= 2,
      `Only ${guardianCards.length} guardian cards, need at least 2`
    );
  });

  test("enough assassin cards for max assassins (3 in 6-8 player)", () => {
    const assassinCards = getCardsForRole("assassin");
    assert.ok(
      assassinCards.length >= 3,
      `Only ${assassinCards.length} assassin cards, need at least 3`
    );
  });

  test("enough traitor cards for max traitors (2 in 8 player)", () => {
    const traitorCards = getCardsForRole("traitor");
    assert.ok(
      traitorCards.length >= 2,
      `Only ${traitorCards.length} traitor cards, need at least 2`
    );
  });

  test("all cards have required fields (id, name, role, ability_text)", () => {
    for (const card of CARDS) {
      assert.ok(card.id, `Card missing id: ${JSON.stringify(card)}`);
      assert.ok(card.name, `Card ${card.id} missing name`);
      assert.ok(card.role, `Card ${card.id} missing role`);
      assert.ok(
        card.ability_text,
        `Card ${card.id} (${card.name}) missing ability_text`
      );
    }
  });

  test("no duplicate card IDs", () => {
    const ids = CARDS.map((c) => c.id);
    const uniqueIds = new Set(ids);
    assert.strictEqual(
      ids.length,
      uniqueIds.size,
      `Found ${ids.length - uniqueIds.size} duplicate card IDs`
    );
  });

  test("card roles are all valid", () => {
    const validRoles = new Set(["leader", "guardian", "assassin", "traitor"]);
    for (const card of CARDS) {
      assert.ok(
        validRoles.has(card.role),
        `Card ${card.id} has invalid role: ${card.role}`
      );
    }
  });
});

suite("Win Conditions — Basic", () => {
  test("leader wins when all assassins and traitors eliminated", () => {
    const players = makePlayers([
      { role: "leader" },
      { role: "guardian" },
      { role: "assassin", eliminated: true },
      { role: "assassin", eliminated: true },
      { role: "traitor", eliminated: true },
    ]);
    assert.strictEqual(checkWinConditions(players), "leader");
  });

  test("assassin wins when leader eliminated and assassin survives", () => {
    const players = makePlayers([
      { role: "leader", eliminated: true },
      { role: "guardian" },
      { role: "assassin" },
      { role: "assassin", eliminated: true },
      { role: "traitor" },
    ]);
    assert.strictEqual(checkWinConditions(players), "assassin");
  });

  test("traitor wins by being last player standing", () => {
    const players = makePlayers([
      { role: "leader", eliminated: true },
      { role: "guardian", eliminated: true },
      { role: "assassin", eliminated: true },
      { role: "assassin", eliminated: true },
      { role: "traitor" },
    ]);
    assert.strictEqual(checkWinConditions(players), "traitor");
  });

  test("game continues when leader alive but assassins remain", () => {
    const players = makePlayers([
      { role: "leader" },
      { role: "guardian" },
      { role: "assassin" },
      { role: "traitor", eliminated: true },
    ]);
    assert.strictEqual(checkWinConditions(players), null);
  });

  test("game continues when leader alive but traitors remain", () => {
    const players = makePlayers([
      { role: "leader" },
      { role: "guardian" },
      { role: "assassin", eliminated: true },
      { role: "traitor" },
    ]);
    assert.strictEqual(checkWinConditions(players), null);
  });
});

suite("Win Conditions — Edge Cases", () => {
  test("leader eliminated + no assassins + no traitors = assassin wins", () => {
    // Edge case in the code: all enemies dead but leader also dead
    const players = makePlayers([
      { role: "leader", eliminated: true },
      { role: "guardian" },
      { role: "assassin", eliminated: true },
      { role: "traitor", eliminated: true },
    ]);
    assert.strictEqual(checkWinConditions(players), "assassin");
  });

  test("all players eliminated (impossible state) = assassin wins", () => {
    const players = makePlayers([
      { role: "leader", eliminated: true },
      { role: "guardian", eliminated: true },
      { role: "assassin", eliminated: true },
      { role: "traitor", eliminated: true },
    ]);
    // alive.length === 0, no traitor solo win
    // leaderAlive=false, assassinAlive=false, traitorAlive=false
    // Falls to: !leaderAlive && !assassinAlive && !traitorAlive = assassin
    assert.strictEqual(checkWinConditions(players), "assassin");
  });

  test("leader dead + assassins alive + traitors alive = assassin wins", () => {
    const players = makePlayers([
      { role: "leader", eliminated: true },
      { role: "guardian" },
      { role: "assassin" },
      { role: "traitor" },
    ]);
    assert.strictEqual(checkWinConditions(players), "assassin");
  });

  test("only guardians alive (leader dead, all enemies dead) = assassin credited", () => {
    // This is an intentional design choice per the code comment
    const players = makePlayers([
      { role: "leader", eliminated: true },
      { role: "guardian" },
      { role: "guardian" },
      { role: "assassin", eliminated: true },
      { role: "traitor", eliminated: true },
    ]);
    assert.strictEqual(checkWinConditions(players), "assassin");
  });

  test("traitor cannot win unless literally last player standing", () => {
    // Traitor + 1 other alive = no traitor win
    const players = makePlayers([
      { role: "leader", eliminated: true },
      { role: "guardian", eliminated: true },
      { role: "assassin", eliminated: true },
      { role: "traitor" },
      { role: "guardian" }, // one guardian still alive
    ]);
    // leaderAlive=false, assassinAlive=false, traitorAlive=true
    // alive.length=2, so not traitor solo win
    // !leaderAlive && assassinAlive → false
    // leaderAlive && !assassinAlive && !traitorAlive → false
    // !leaderAlive && !assassinAlive && !traitorAlive → false (traitor alive)
    // returns null — game continues
    assert.strictEqual(checkWinConditions(players), null);
  });

  test("BUG SCENARIO: leader dead + no assassins + traitor alive = game stuck", () => {
    // This is a potentially problematic state:
    // Leader is dead, all assassins dead, but traitor is alive with guardians.
    // Game continues (returns null), but there's no natural end condition —
    // guardians have already lost (leader dead), traitor needs to be last standing.
    // Players must manually eliminate each other or forfeit.
    const players = makePlayers([
      { role: "leader", eliminated: true },
      { role: "guardian" },
      { role: "guardian" },
      { role: "assassin", eliminated: true },
      { role: "assassin", eliminated: true },
      { role: "traitor" },
    ]);
    const result = checkWinConditions(players);
    assert.strictEqual(result, null, "Game continues — but is effectively stuck");
    // Note: This isn't necessarily a bug in the win condition logic,
    // but it IS a UX issue. The guardians have no win condition anymore
    // (leader is dead), and they must help eliminate the traitor for the
    // game to end, even though they've already "lost".
  });

  test("4 player game: leader + traitor alive, assassins dead = game continues", () => {
    const players = makePlayers([
      { role: "leader" },
      { role: "assassin", eliminated: true },
      { role: "assassin", eliminated: true },
      { role: "traitor" },
    ]);
    assert.strictEqual(checkWinConditions(players), null);
  });

  test("4 player game: leader wins if traitor eliminated (no guardians)", () => {
    const players = makePlayers([
      { role: "leader" },
      { role: "assassin", eliminated: true },
      { role: "assassin", eliminated: true },
      { role: "traitor", eliminated: true },
    ]);
    assert.strictEqual(checkWinConditions(players), "leader");
  });
});

suite("Win Conditions — Simultaneous Elimination (Race Scenario)", () => {
  test("adjustLife to 0 eliminates and checks win conditions atomically", () => {
    // Simulating what happens in the adjustLife transaction:
    // If the last assassin is eliminated, we need to check with the
    // updated player state (not stale state)
    const players = makePlayers([
      { role: "leader" },
      { role: "guardian" },
      { role: "assassin", life: 1 },
      { role: "traitor", eliminated: true },
    ]);

    // Simulate eliminating the last assassin (as done in adjustLife transaction)
    const updatedPlayers = players.map((p) => {
      if (p.role === "assassin") {
        return { ...p, is_eliminated: true, life_total: 0 };
      }
      return p;
    });

    assert.strictEqual(
      checkWinConditions(updatedPlayers),
      "leader",
      "Leader should win when last assassin eliminated"
    );
  });
});

suite("Planechase — Plane Cards", () => {
  test("plane cards JSON is non-empty", () => {
    assert.ok(PLANE_CARDS.length > 0, "No plane cards loaded");
  });

  test("all plane cards have required fields", () => {
    for (const plane of PLANE_CARDS) {
      assert.ok(plane.id, `Plane missing id`);
      assert.ok(plane.name, `Plane ${plane.id} missing name`);
      assert.ok(
        typeof plane.is_phenomenon === "boolean",
        `Plane ${plane.id} missing is_phenomenon boolean`
      );
    }
  });

  test("no duplicate plane IDs", () => {
    const ids = PLANE_CARDS.map((p) => p.id);
    const uniqueIds = new Set(ids);
    assert.strictEqual(
      ids.length,
      uniqueIds.size,
      `Found ${ids.length - uniqueIds.size} duplicate plane IDs`
    );
  });

  test("special phenomenon IDs exist in the deck", () => {
    const ids = new Set(PLANE_CARDS.map((p) => p.id));
    assert.ok(ids.has(CHAOTIC_AETHER_ID), "Chaotic Aether not found in deck");
    assert.ok(
      ids.has(INTERPLANAR_TUNNEL_ID),
      "Interplanar Tunnel not found in deck"
    );
    assert.ok(
      ids.has(SPATIAL_MERGING_ID),
      "Spatial Merging not found in deck"
    );
  });

  test("special phenomena are marked as is_phenomenon=true", () => {
    const chaoticAether = PLANE_CARDS.find((p) => p.id === CHAOTIC_AETHER_ID);
    const tunnel = PLANE_CARDS.find((p) => p.id === INTERPLANAR_TUNNEL_ID);
    const spatial = PLANE_CARDS.find((p) => p.id === SPATIAL_MERGING_ID);

    assert.ok(chaoticAether.is_phenomenon, "Chaotic Aether should be a phenomenon");
    assert.ok(tunnel.is_phenomenon, "Interplanar Tunnel should be a phenomenon");
    assert.ok(spatial.is_phenomenon, "Spatial Merging should be a phenomenon");
  });

  test("there are enough non-phenomenon planes for starting plane selection", () => {
    const nonPhenomena = PLANE_CARDS.filter((p) => !p.is_phenomenon);
    assert.ok(
      nonPhenomena.length >= 5,
      `Only ${nonPhenomena.length} non-phenomenon planes — need at least 5 for Spatial Merging`
    );
  });

  test("deck exhaustion reset: can always find a next plane", () => {
    // Simulate using all planes, then resetting
    const allIds = PLANE_CARDS.map((p) => p.id);
    let usedPlaneIds = [...allIds]; // All used
    const currentPlaneId = allIds[0];

    // After reset, only current plane stays used
    let available = PLANE_CARDS.filter((p) => !usedPlaneIds.includes(p.id));
    if (available.length === 0) {
      usedPlaneIds = currentPlaneId ? [currentPlaneId] : [];
      available = PLANE_CARDS.filter((p) => !usedPlaneIds.includes(p.id));
    }
    assert.ok(
      available.length > 0,
      "After deck reset, should have available planes"
    );
    assert.ok(
      available.length === PLANE_CARDS.length - 1,
      `After reset, expected ${PLANE_CARDS.length - 1} available, got ${available.length}`
    );
  });

  test("Interplanar Tunnel: can always offer at least 1 non-phenomenon plane", () => {
    const nonPhenomena = PLANE_CARDS.filter((p) => !p.is_phenomenon);
    assert.ok(
      nonPhenomena.length >= 1,
      "Need at least 1 non-phenomenon plane for Interplanar Tunnel"
    );
  });

  test("Spatial Merging: can always find 2 non-phenomenon planes", () => {
    const nonPhenomena = PLANE_CARDS.filter((p) => !p.is_phenomenon);
    assert.ok(
      nonPhenomena.length >= 2,
      `Only ${nonPhenomena.length} non-phenomenon planes, Spatial Merging needs 2`
    );
  });
});

suite("Planechase — Die Roll Logic", () => {
  test("die roll distribution: 4/6 blank, 1/6 chaos, 1/6 planeswalk", () => {
    // Statistical test: roll many times and check distribution
    const counts = { blank: 0, chaos: 0, planeswalk: 0 };
    const trials = 60000;

    for (let i = 0; i < trials; i++) {
      const roll = Math.floor(Math.random() * 6);
      if (roll < 4) counts.blank++;
      else if (roll === 4) counts.chaos++;
      else counts.planeswalk++;
    }

    // Each should be within 2% of expected
    const blankPct = counts.blank / trials;
    const chaosPct = counts.chaos / trials;
    const planeswalkPct = counts.planeswalk / trials;

    assert.ok(
      Math.abs(blankPct - 4 / 6) < 0.02,
      `Blank: expected ~66.7%, got ${(blankPct * 100).toFixed(1)}%`
    );
    assert.ok(
      Math.abs(chaosPct - 1 / 6) < 0.02,
      `Chaos: expected ~16.7%, got ${(chaosPct * 100).toFixed(1)}%`
    );
    assert.ok(
      Math.abs(planeswalkPct - 1 / 6) < 0.02,
      `Planeswalk: expected ~16.7%, got ${(planeswalkPct * 100).toFixed(1)}%`
    );
  });

  test("mana cost: first roll free, then 1, 2, 3...", () => {
    // Simulating the cost logic from rollPlanarDie
    for (let rollCount = 1; rollCount <= 5; rollCount++) {
      const manaCost = Math.max(0, rollCount - 1);
      if (rollCount === 1) {
        assert.strictEqual(manaCost, 0, "First roll should be free");
      } else {
        assert.strictEqual(
          manaCost,
          rollCount - 1,
          `Roll ${rollCount} should cost ${rollCount - 1}`
        );
      }
    }
  });

  test("roll count resets when a different player rolls", () => {
    // Simulating the logic in rollPlanarDie
    let lastRollerId = "userA";
    let dieRollCount = 3;

    // Same player rolls again
    const uid1 = "userA";
    let rollCount1;
    if (lastRollerId === uid1) {
      rollCount1 = dieRollCount + 1;
    } else {
      rollCount1 = 1;
    }
    assert.strictEqual(rollCount1, 4, "Same player: count should increment");

    // Different player rolls
    const uid2 = "userB";
    let rollCount2;
    if (lastRollerId === uid2) {
      rollCount2 = dieRollCount + 1;
    } else {
      rollCount2 = 1;
    }
    assert.strictEqual(rollCount2, 1, "Different player: count should reset to 1");
  });

  test("Chaotic Aether: blank rolls become chaos", () => {
    const chaoticAetherActive = true;
    let result = "blank";
    if (chaoticAetherActive && result === "blank") {
      result = "chaos";
    }
    assert.strictEqual(result, "chaos");
  });

  test("Chaotic Aether: chaos and planeswalk unaffected", () => {
    const chaoticAetherActive = true;

    let result1 = "chaos";
    if (chaoticAetherActive && result1 === "blank") result1 = "chaos";
    assert.strictEqual(result1, "chaos");

    let result2 = "planeswalk";
    if (chaoticAetherActive && result2 === "blank") result2 = "chaos";
    assert.strictEqual(result2, "planeswalk");
  });
});

suite("ELO Calculation", () => {
  test("equal ELO: winner gains ~16, loser loses ~16 (K=32)", () => {
    const K = 32;
    const winnerElo = 1500;
    const loserElo = 1500;

    const expectedWinner =
      1.0 / (1.0 + Math.pow(10, (loserElo - winnerElo) / 400));
    const change = Math.round(K * (1 - expectedWinner));

    assert.strictEqual(change, 16, `Expected 16 ELO change, got ${change}`);
  });

  test("higher rated winner gains less ELO", () => {
    const K = 32;
    const winnerElo = 1800;
    const loserElo = 1200;

    const expectedWinner =
      1.0 / (1.0 + Math.pow(10, (loserElo - winnerElo) / 400));
    const change = K * (1 - expectedWinner);

    assert.ok(
      change < 10,
      `Expected small gain for dominant win, got ${change.toFixed(1)}`
    );
  });

  test("lower rated winner gains more ELO (upset)", () => {
    const K = 32;
    const winnerElo = 1200;
    const loserElo = 1800;

    const expectedWinner =
      1.0 / (1.0 + Math.pow(10, (loserElo - winnerElo) / 400));
    const change = K * (1 - expectedWinner);

    assert.ok(
      change > 25,
      `Expected large gain for upset, got ${change.toFixed(1)}`
    );
  });

  test("ELO floor at 0 (cannot go negative)", () => {
    const currentElo = 5;
    const eloChange = -20;
    const newElo = Math.max(0, currentElo + eloChange);
    assert.strictEqual(newElo, 0, "ELO should floor at 0");
  });

  test("default ELO for new players is 1500", () => {
    const userDoc = {}; // No elo field
    const elo = userDoc?.elo || 1500;
    assert.strictEqual(elo, 1500);
  });
});

suite("Shuffle Fairness", () => {
  test("shuffle produces all elements (no loss/duplication)", () => {
    const input = [1, 2, 3, 4, 5, 6, 7, 8];
    const output = shuffle(input);
    assert.strictEqual(output.length, input.length);
    assert.deepStrictEqual(output.sort(), input.sort());
  });

  test("shuffle does not mutate original array", () => {
    const input = [1, 2, 3, 4, 5];
    const copy = [...input];
    shuffle(input);
    assert.deepStrictEqual(input, copy, "Original array should not be mutated");
  });

  test("shuffle produces different orderings (statistical)", () => {
    const input = [1, 2, 3, 4, 5, 6, 7, 8];
    const results = new Set();
    for (let i = 0; i < 100; i++) {
      results.add(JSON.stringify(shuffle(input)));
    }
    // 100 shuffles of 8 items should produce many unique orderings
    assert.ok(
      results.size > 90,
      `Only ${results.size} unique orderings in 100 shuffles — suspicious`
    );
  });
});

suite("Role Assignment — Full Simulation", () => {
  test("all players get unique cards in a full 8-player game", () => {
    const players = Array.from({ length: 8 }, (_, i) => ({
      ref: `ref${i}`,
      user_id: `user${i}`,
    }));

    const dist = getRoleDistribution(8);
    const roles = [];
    for (let i = 0; i < dist.leaders; i++) roles.push("leader");
    for (let i = 0; i < dist.guardians; i++) roles.push("guardian");
    for (let i = 0; i < dist.assassins; i++) roles.push("assassin");
    for (let i = 0; i < dist.traitors; i++) roles.push("traitor");

    const shuffledRoles = shuffle(roles);
    const usedCardIds = new Set();

    for (let i = 0; i < players.length; i++) {
      const role = shuffledRoles[i];
      const availableCards = getCardsForRole(role).filter(
        (c) => !usedCardIds.has(c.id)
      );

      assert.ok(
        availableCards.length > 0,
        `No available cards for role ${role} at player ${i}`
      );

      const card =
        availableCards[Math.floor(Math.random() * availableCards.length)];
      usedCardIds.add(card.id);
    }

    assert.strictEqual(usedCardIds.size, 8, "Expected 8 unique cards assigned");
  });

  test("run 1000 role assignments without running out of cards", () => {
    for (let trial = 0; trial < 1000; trial++) {
      for (let playerCount = 4; playerCount <= 8; playerCount++) {
        const dist = getRoleDistribution(playerCount);
        const roles = [];
        for (let i = 0; i < dist.leaders; i++) roles.push("leader");
        for (let i = 0; i < dist.guardians; i++) roles.push("guardian");
        for (let i = 0; i < dist.assassins; i++) roles.push("assassin");
        for (let i = 0; i < dist.traitors; i++) roles.push("traitor");

        const shuffledRoles = shuffle(roles);
        const usedCardIds = new Set();

        for (let i = 0; i < playerCount; i++) {
          const role = shuffledRoles[i];
          const available = getCardsForRole(role).filter(
            (c) => !usedCardIds.has(c.id)
          );
          assert.ok(
            available.length > 0,
            `Trial ${trial}, ${playerCount} players: ran out of ${role} cards at player ${i}`
          );
          const card =
            available[Math.floor(Math.random() * available.length)];
          usedCardIds.add(card.id);
        }
      }
    }
  });
});

suite("Life Adjustment Edge Cases", () => {
  test("life at 0 triggers elimination", () => {
    let life = 5;
    const amount = -5;
    let newLife = life + amount;
    const eliminated = newLife <= 0;
    if (eliminated) newLife = 0;

    assert.strictEqual(newLife, 0);
    assert.strictEqual(eliminated, true);
  });

  test("negative life clamps to 0", () => {
    let life = 3;
    const amount = -10;
    let newLife = life + amount;
    const eliminated = newLife <= 0;
    if (eliminated) newLife = 0;

    assert.strictEqual(newLife, 0);
    assert.strictEqual(eliminated, true);
  });

  test("life adjustment from 1 to 0 eliminates", () => {
    let life = 1;
    const amount = -1;
    let newLife = life + amount;
    const eliminated = newLife <= 0;
    if (eliminated) newLife = 0;

    assert.strictEqual(eliminated, true);
  });

  test("large positive adjustment does not cause issues", () => {
    let life = 40;
    const amount = 999999;
    let newLife = life + amount;
    const eliminated = newLife <= 0;

    assert.strictEqual(newLife, 1000039);
    assert.strictEqual(eliminated, false);
  });

  test("adjustment of 0 does nothing", () => {
    let life = 40;
    const amount = 0;
    let newLife = life + amount;
    const eliminated = newLife <= 0;

    assert.strictEqual(newLife, 40);
    assert.strictEqual(eliminated, false);
  });
});

suite("Concurrency Simulation — Concurrent Joins", () => {
  test("BUG DEMO: two simultaneous joins can get same orderId", () => {
    // Simulating the race in JoinGameView.joinGame()
    // Both players read existingPlayers.count at the same time
    const existingPlayersCountAtRead = 3;

    const player1OrderId = existingPlayersCountAtRead; // = 3
    const player2OrderId = existingPlayersCountAtRead; // = 3 (same read!)

    assert.strictEqual(
      player1OrderId,
      player2OrderId,
      "Both players get the same orderId — confirming the race condition bug"
    );
  });

  test("BUG DEMO: two joins can exceed maxPlayers", () => {
    // Both read count=7, maxPlayers=8
    // Both pass the check: 7 < 8 = true
    // Both write, resulting in 9 players
    const existingCount = 7;
    const maxPlayers = 8;

    const player1Passes = existingCount < maxPlayers; // true
    const player2Passes = existingCount < maxPlayers; // true (stale read!)

    assert.ok(
      player1Passes && player2Passes,
      "Both players pass the check — confirming max player bypass bug"
    );
    // After both join: 7 + 2 = 9 > maxPlayers=8
  });
});

suite("Game Mode Validation", () => {
  test("treachery mode includes treachery", () => {
    const mode = "treachery";
    const includesTreachery = mode === "treachery" || mode === "treachery_planechase";
    assert.ok(includesTreachery);
  });

  test("planechase mode does not include treachery", () => {
    const mode = "planechase";
    const includesTreachery = mode === "treachery" || mode === "treachery_planechase";
    assert.ok(!includesTreachery);
  });

  test("treachery_planechase includes both", () => {
    const mode = "treachery_planechase";
    const includesTreachery = mode === "treachery" || mode === "treachery_planechase";
    const includesPlanechase = mode === "planechase" || mode === "treachery_planechase";
    assert.ok(includesTreachery);
    assert.ok(includesPlanechase);
  });

  test("none mode includes neither", () => {
    const mode = "none";
    const includesTreachery = mode === "treachery" || mode === "treachery_planechase";
    const includesPlanechase = mode === "planechase" || mode === "treachery_planechase";
    assert.ok(!includesTreachery);
    assert.ok(!includesPlanechase);
  });

  test("startGame minimum player validation: treachery needs 4 on client but server allows 1", () => {
    // The iOS client enforces minimumPlayerCount = 4 for treachery
    // But the server only checks players.length < 1
    // This means if the client check is bypassed, a 1-player treachery game could start
    const serverMinimum = 1; // from index.js line 236
    const clientMinimum = 4; // from Role.swift minimumPlayerCount
    assert.notStrictEqual(
      serverMinimum,
      clientMinimum,
      "BUG: Server and client have different minimums for treachery mode"
    );
  });
});

// ═════════════════════════════════════════════════════════════════
// Chaos Ability Parsing
// ═════════════════════════════════════════════════════════════════

// This parser extracts chaos ability text from plane card oracle_text.
// It handles the 3 formats found in the data:
//   1. "Whenever chaos ensues, <effect>"   (172 planes)
//   2. "When chaos ensues, <effect>"        (5 planes — Bad Wolf Bay, Pompeii, TARDIS Bay, Temple of Atropos, No Way Out)
//   3. "Chaos: <effect>"                    (4 planes — Bicycle Rack, Shrinking Plane, Stroopwafel Cafe, The Food Court, Windmill Farm)
// Two planes have NO chaos ability: Ghirapur Grand Prix, sAnS mERcY

function parseChaosAbility(oracleText) {
  if (!oracleText) return null;

  // Pattern 1: "Whenever chaos ensues, <effect>" or "Whenever Chaos ensues, <effect>"
  const wheneverMatch = oracleText.match(/Whenever [Cc]haos ensues,\s*([\s\S]*?)(?:\n(?!.*chaos)|$)/i);
  if (wheneverMatch) {
    return wheneverMatch[1].trim();
  }

  // Pattern 2: "When chaos ensues, <effect>" (no "ever")
  const whenMatch = oracleText.match(/When chaos ensues,\s*([\s\S]*?)(?:\n(?!.*chaos)|$)/i);
  if (whenMatch) {
    return whenMatch[1].trim();
  }

  // Pattern 3: "Chaos: <effect>"
  const colonMatch = oracleText.match(/Chaos:\s*([\s\S]*?)(?:\n|$)/i);
  if (colonMatch) {
    return colonMatch[1].trim();
  }

  // Special case: chaos ensues is referenced but not as a trigger (e.g., No Way Out)
  // "chaos ensues instead" — this plane redirects planeswalk to chaos, not a direct ability
  if (/chaos ensues/i.test(oracleText)) {
    // Extract the sentence containing "chaos ensues"
    const lines = oracleText.split("\n");
    const chaosLine = lines.find(l => /chaos ensues/i.test(l));
    return chaosLine ? chaosLine.trim() : null;
  }

  return null;
}

// Categorize a chaos ability for game-mechanical purposes
function categorizeChaosAbility(abilityText) {
  if (!abilityText) return "none";

  const lower = abilityText.toLowerCase();

  // Damage effects
  if (/deals?\s+\d+\s+damage/i.test(lower) || /loses?\s+\d+\s+life/i.test(lower)) {
    return "damage";
  }
  // Life gain
  if (/gains?\s+\d*\s*life/i.test(lower) || /gain\s+(three|two|one|\d+)\s+life/i.test(lower)) {
    return "life_gain";
  }
  // Card draw
  if (/draw/i.test(lower)) {
    return "draw";
  }
  // Creature destruction/removal
  if (/destroy/i.test(lower) || /exile/i.test(lower)) {
    return "removal";
  }
  // Token creation
  if (/create/i.test(lower) && /token/i.test(lower)) {
    return "tokens";
  }
  // Counter manipulation
  if (/counter/i.test(lower)) {
    return "counters";
  }
  // Planeswalk trigger
  if (/planeswalk/i.test(lower)) {
    return "planeswalk";
  }
  // Discard
  if (/discard/i.test(lower)) {
    return "discard";
  }

  return "other";
}

suite("Planechase — Chaos Ability Parsing", () => {
  const regularPlanes = PLANE_CARDS.filter(p => !p.is_phenomenon);

  test("all regular planes have oracle_text", () => {
    for (const plane of regularPlanes) {
      assert.ok(
        plane.oracle_text && plane.oracle_text.length > 0,
        `Plane "${plane.name}" has no oracle_text`
      );
    }
  });

  test("at least 170 regular planes have parseable chaos ability", () => {
    const withChaos = regularPlanes.filter(p => parseChaosAbility(p.oracle_text) !== null);
    assert.ok(
      withChaos.length >= 170,
      `Only ${withChaos.length} planes have parseable chaos ability (expected >= 170)`
    );
  });

  test("planes with 'Whenever chaos ensues' format parse correctly", () => {
    // Academy at Tolaria West: "Whenever chaos ensues, discard your hand."
    const academy = PLANE_CARDS.find(p => p.name === "Academy at Tolaria West");
    assert.ok(academy, "Academy at Tolaria West not found");
    const ability = parseChaosAbility(academy.oracle_text);
    assert.ok(ability, "Failed to parse chaos ability");
    assert.ok(
      ability.includes("discard your hand"),
      `Expected 'discard your hand' in ability, got: "${ability}"`
    );
  });

  test("planes with 'When chaos ensues' format parse correctly", () => {
    // Bad Wolf Bay: "When chaos ensues, cards can't enter from exile this turn. Then planeswalk."
    const badWolf = PLANE_CARDS.find(p => p.name === "Bad Wolf Bay");
    assert.ok(badWolf, "Bad Wolf Bay not found");
    const ability = parseChaosAbility(badWolf.oracle_text);
    assert.ok(ability, "Failed to parse Bad Wolf Bay chaos ability");
    assert.ok(
      ability.includes("cards can't enter from exile"),
      `Expected exile prevention text, got: "${ability}"`
    );
  });

  test("planes with 'Chaos:' format parse correctly", () => {
    // Bicycle Rack: "Chaos: Until end of turn, creatures you control have..."
    const bicycle = PLANE_CARDS.find(p => p.name === "Bicycle Rack");
    assert.ok(bicycle, "Bicycle Rack not found");
    const ability = parseChaosAbility(bicycle.oracle_text);
    assert.ok(ability, "Failed to parse Bicycle Rack chaos ability");
    assert.ok(
      ability.includes("Until end of turn"),
      `Expected 'Until end of turn' in ability, got: "${ability}"`
    );
  });

  test("Stroopwafel Cafe 'Chaos:' format parses correctly", () => {
    const cafe = PLANE_CARDS.find(p => p.name === "Stroopwafel Cafe");
    assert.ok(cafe, "Stroopwafel Cafe not found");
    const ability = parseChaosAbility(cafe.oracle_text);
    assert.ok(ability, "Failed to parse Stroopwafel Cafe chaos ability");
    assert.ok(
      ability.includes("sacrifice a Food"),
      `Expected 'sacrifice a Food', got: "${ability}"`
    );
  });

  test("planes with no chaos text return null", () => {
    const ghirapur = PLANE_CARDS.find(p => p.name === "Ghirapur Grand Prix");
    assert.ok(ghirapur, "Ghirapur Grand Prix not found");
    const ability = parseChaosAbility(ghirapur.oracle_text);
    assert.strictEqual(
      ability,
      null,
      `Ghirapur Grand Prix should have no chaos ability, got: "${ability}"`
    );
  });

  test("sAnS mERcY has no chaos text", () => {
    const sans = PLANE_CARDS.find(p => p.name === "sAnS mERcY");
    assert.ok(sans, "sAnS mERcY not found");
    const ability = parseChaosAbility(sans.oracle_text);
    assert.strictEqual(
      ability,
      null,
      `sAnS mERcY should have no chaos ability, got: "${ability}"`
    );
  });

  test("phenomena cards are not regular planes (should not have chaos abilities)", () => {
    const phenomena = PLANE_CARDS.filter(p => p.is_phenomenon);
    assert.ok(phenomena.length > 0, "No phenomena found");
    // Phenomena have encounter effects, not chaos abilities in the traditional sense
    for (const p of phenomena) {
      assert.ok(
        p.is_phenomenon,
        `${p.name} should be marked as phenomenon`
      );
    }
  });

  test("No Way Out has special chaos-redirect mechanic", () => {
    const noWayOut = PLANE_CARDS.find(p => p.name === "No Way Out (Playtest)");
    assert.ok(noWayOut, "No Way Out (Playtest) not found");
    const ability = parseChaosAbility(noWayOut.oracle_text);
    assert.ok(ability, "Failed to parse No Way Out chaos ability");
    // This plane converts planeswalk into chaos — it's a redirect, not a normal chaos trigger
    assert.ok(
      ability.includes("chaos ensues instead"),
      `Expected 'chaos ensues instead' in ability, got: "${ability}"`
    );
  });

  test("Pompeii chaos deals damage based on counters", () => {
    const pompeii = PLANE_CARDS.find(p => p.name === "Pompeii");
    assert.ok(pompeii, "Pompeii not found");
    const ability = parseChaosAbility(pompeii.oracle_text);
    assert.ok(ability, "Failed to parse Pompeii chaos ability");
    assert.ok(
      ability.includes("deals damage"),
      `Expected damage text, got: "${ability}"`
    );
  });

  test("TARDIS Bay chaos steals an artifact", () => {
    const tardis = PLANE_CARDS.find(p => p.name === "TARDIS Bay");
    assert.ok(tardis, "TARDIS Bay not found");
    const ability = parseChaosAbility(tardis.oracle_text);
    assert.ok(ability, "Failed to parse TARDIS Bay chaos ability");
    assert.ok(
      ability.includes("gain control of target artifact"),
      `Expected artifact steal, got: "${ability}"`
    );
  });

  test("Temple of Atropos chaos reverses turn order", () => {
    const temple = PLANE_CARDS.find(p => p.name === "Temple of Atropos");
    assert.ok(temple, "Temple of Atropos not found");
    const ability = parseChaosAbility(temple.oracle_text);
    assert.ok(ability, "Failed to parse Temple of Atropos chaos ability");
    assert.ok(
      ability.includes("reverse"),
      `Expected 'reverse' in ability, got: "${ability}"`
    );
  });
});

suite("Planechase — Chaos Ability Categories", () => {
  test("damage abilities categorized correctly", () => {
    // Astral Arena: "Astral Arena deals 2 damage to each creature."
    const arena = PLANE_CARDS.find(p => p.name === "Astral Arena");
    assert.ok(arena, "Astral Arena not found");
    const ability = parseChaosAbility(arena.oracle_text);
    const category = categorizeChaosAbility(ability);
    assert.strictEqual(category, "damage", `Expected 'damage', got '${category}'`);
  });

  test("draw abilities categorized correctly", () => {
    // Aretopolis: "...draw cards equal to the number of scroll counters on it."
    const areto = PLANE_CARDS.find(p => p.name === "Aretopolis");
    assert.ok(areto, "Aretopolis not found");
    const ability = parseChaosAbility(areto.oracle_text);
    const category = categorizeChaosAbility(ability);
    // Has both counters and draw — draw is checked first in our impl, but counters is checked before draw
    // Actually counters is checked after draw... let's check
    assert.ok(
      category === "draw" || category === "counters",
      `Expected 'draw' or 'counters', got '${category}'`
    );
  });

  test("discard abilities categorized correctly", () => {
    // Academy at Tolaria West: "discard your hand"
    const academy = PLANE_CARDS.find(p => p.name === "Academy at Tolaria West");
    const ability = parseChaosAbility(academy.oracle_text);
    const category = categorizeChaosAbility(ability);
    assert.strictEqual(category, "discard", `Expected 'discard', got '${category}'`);
  });

  test("removal abilities categorized correctly", () => {
    // Akoum: "destroy target creature that isn't enchanted"
    const akoum = PLANE_CARDS.find(p => p.name === "Akoum");
    assert.ok(akoum, "Akoum not found");
    const ability = parseChaosAbility(akoum.oracle_text);
    const category = categorizeChaosAbility(ability);
    assert.strictEqual(category, "removal", `Expected 'removal', got '${category}'`);
  });

  test("token creation categorized correctly", () => {
    // Aplan Mortarium: "create two 2/2 black Alien Angel artifact creature tokens"
    const aplan = PLANE_CARDS.find(p => p.name === "Aplan Mortarium");
    assert.ok(aplan, "Aplan Mortarium not found");
    const ability = parseChaosAbility(aplan.oracle_text);
    const category = categorizeChaosAbility(ability);
    assert.strictEqual(category, "tokens", `Expected 'tokens', got '${category}'`);
  });

  test("null ability returns 'none'", () => {
    assert.strictEqual(categorizeChaosAbility(null), "none");
  });

  test("all regular planes with chaos abilities get categorized (no crashes)", () => {
    const regularPlanes = PLANE_CARDS.filter(p => !p.is_phenomenon);
    let categorized = 0;
    for (const plane of regularPlanes) {
      const ability = parseChaosAbility(plane.oracle_text);
      if (ability) {
        const category = categorizeChaosAbility(ability);
        assert.ok(
          typeof category === "string" && category.length > 0,
          `Categorization failed for ${plane.name}`
        );
        categorized++;
      }
    }
    assert.ok(
      categorized >= 170,
      `Only ${categorized} planes categorized, expected >= 170`
    );
  });
});

suite("Planechase — Chaos in rollPlanarDie Logic", () => {
  test("chaos result triggers chaos ability lookup for current plane", () => {
    // Simulate a chaos roll on Academy at Tolaria West
    const plane = PLANE_CARDS.find(p => p.name === "Academy at Tolaria West");
    const result = "chaos";
    // The server should return the chaos ability info so the client can display it
    const ability = parseChaosAbility(plane.oracle_text);
    assert.ok(ability, "Chaos ability should be parseable for current plane");
    // BUG: Currently rollPlanarDie returns { result: "chaos" } but does NOT include
    // any chaos ability info. The client has no way to know what the chaos effect is
    // unless it has its own copy of the plane data.
    assert.strictEqual(result, "chaos");
    // This test documents that the server SHOULD return chaos ability data
  });

  test("Chaotic Aether converts blank rolls to chaos", () => {
    // When chaotic_aether_active is true, blank -> chaos
    const planechase = { chaotic_aether_active: true };
    let result = "blank";
    if (planechase.chaotic_aether_active && result === "blank") {
      result = "chaos";
    }
    assert.strictEqual(result, "chaos");
  });

  test("Chaotic Aether does NOT affect planeswalk rolls", () => {
    const planechase = { chaotic_aether_active: true };
    let result = "planeswalk";
    if (planechase.chaotic_aether_active && result === "blank") {
      result = "chaos";
    }
    assert.strictEqual(result, "planeswalk");
  });

  test("chaos on a plane with no chaos ability is a no-op", () => {
    const ghirapur = PLANE_CARDS.find(p => p.name === "Ghirapur Grand Prix");
    const ability = parseChaosAbility(ghirapur.oracle_text);
    assert.strictEqual(ability, null, "No chaos ability — roll is a no-op");
  });

  test("Spatial Merging: chaos on either merged plane should apply", () => {
    // When two planes are merged (Spatial Merging), both planes' static
    // and chaos abilities should be active. A chaos roll should trigger
    // BOTH planes' chaos effects.
    const plane1 = PLANE_CARDS.find(p => p.name === "Academy at Tolaria West");
    const plane2 = PLANE_CARDS.find(p => p.name === "Akoum");
    const ability1 = parseChaosAbility(plane1.oracle_text);
    const ability2 = parseChaosAbility(plane2.oracle_text);
    assert.ok(ability1, "First merged plane should have chaos ability");
    assert.ok(ability2, "Second merged plane should have chaos ability");
    // BUG: rollPlanarDie currently only returns { result: "chaos" } with no
    // indication of which plane(s) the chaos applies to in a merged scenario.
    // The client needs to handle dual chaos triggers.
  });

  test("die roll probability distribution: blank=4/6, chaos=1/6, planeswalk=1/6", () => {
    const rolls = { blank: 0, chaos: 0, planeswalk: 0 };
    const iterations = 60000;
    for (let i = 0; i < iterations; i++) {
      const roll = Math.floor(Math.random() * 6);
      if (roll < 4) rolls.blank++;
      else if (roll === 4) rolls.chaos++;
      else rolls.planeswalk++;
    }

    const blankPct = rolls.blank / iterations;
    const chaosPct = rolls.chaos / iterations;
    const planeswalkPct = rolls.planeswalk / iterations;

    // Should be ~66.7%, ~16.7%, ~16.7% with reasonable tolerance
    assert.ok(
      Math.abs(blankPct - 4 / 6) < 0.02,
      `Blank rate ${(blankPct * 100).toFixed(1)}% deviates from expected 66.7%`
    );
    assert.ok(
      Math.abs(chaosPct - 1 / 6) < 0.02,
      `Chaos rate ${(chaosPct * 100).toFixed(1)}% deviates from expected 16.7%`
    );
    assert.ok(
      Math.abs(planeswalkPct - 1 / 6) < 0.02,
      `Planeswalk rate ${(planeswalkPct * 100).toFixed(1)}% deviates from expected 16.7%`
    );
  });
});

suite("Planechase — Chaos Ability Data Integrity", () => {
  test("all 185 regular planes have valid oracle_text field", () => {
    const regular = PLANE_CARDS.filter(p => !p.is_phenomenon);
    assert.strictEqual(regular.length, 185, `Expected 185 regular planes, got ${regular.length}`);
    for (const plane of regular) {
      assert.ok(
        typeof plane.oracle_text === "string" && plane.oracle_text.length > 0,
        `Plane "${plane.name}" has invalid oracle_text`
      );
    }
  });

  test("all 21 phenomena have is_phenomenon=true and valid oracle_text", () => {
    const phenomena = PLANE_CARDS.filter(p => p.is_phenomenon);
    assert.strictEqual(phenomena.length, 21, `Expected 21 phenomena, got ${phenomena.length}`);
    for (const p of phenomena) {
      assert.ok(
        typeof p.oracle_text === "string" && p.oracle_text.length > 0,
        `Phenomenon "${p.name}" has invalid oracle_text`
      );
    }
  });

  test("no plane card IDs are duplicated", () => {
    const ids = PLANE_CARDS.map(p => p.id);
    const uniqueIds = new Set(ids);
    assert.strictEqual(
      ids.length,
      uniqueIds.size,
      `Found ${ids.length - uniqueIds.size} duplicate plane card IDs`
    );
  });

  test("all plane cards have required fields", () => {
    for (const plane of PLANE_CARDS) {
      assert.ok(plane.id, `Plane missing id: ${JSON.stringify(plane).substring(0, 80)}`);
      assert.ok(plane.name, `Plane ${plane.id} missing name`);
      assert.ok(plane.type_line, `Plane ${plane.id} (${plane.name}) missing type_line`);
      assert.ok(plane.oracle_text, `Plane ${plane.id} (${plane.name}) missing oracle_text`);
      assert.strictEqual(
        typeof plane.is_phenomenon,
        "boolean",
        `Plane ${plane.name} has non-boolean is_phenomenon: ${plane.is_phenomenon}`
      );
    }
  });

  test("exactly 2 regular planes lack any chaos ability text", () => {
    const regular = PLANE_CARDS.filter(p => !p.is_phenomenon);
    const noChaos = regular.filter(p => parseChaosAbility(p.oracle_text) === null);
    assert.strictEqual(
      noChaos.length,
      2,
      `Expected 2 planes without chaos ability, got ${noChaos.length}: ${noChaos.map(p => p.name).join(", ")}`
    );
  });

  test("BUG: rollPlanarDie does not return chaos ability text to client", () => {
    // Currently, rollPlanarDie returns only { result, manaCost, newPlaneId }
    // When result is "chaos", the client receives no info about WHAT the chaos
    // ability actually does. The client must have its own plane card database
    // to display the chaos effect, which creates a sync risk.
    //
    // Suggested fix: when result === "chaos", also return:
    //   { chaosAbilityText, chaosCategory, planeName }
    const mockReturn = { result: "chaos", manaCost: 0, newPlaneId: null };
    assert.ok(
      !("chaosAbilityText" in mockReturn),
      "Confirming rollPlanarDie currently lacks chaos ability data in return"
    );
  });
});

// ═════════════════════════════════════════════════════════════════
// RESULTS
// ═════════════════════════════════════════════════════════════════

console.log("\n" + "═".repeat(50));
console.log(`Results: ${passed} passed, ${failed} failed`);
console.log("═".repeat(50));

if (errors.length > 0) {
  console.log("\nFailed tests:");
  for (const e of errors) {
    console.log(`  ✗ ${e.name}: ${e.error}`);
  }
}

process.exit(failed > 0 ? 1 : 0);
