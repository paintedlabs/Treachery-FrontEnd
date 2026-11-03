// Treachery game rules: role distribution, the dealing shuffle, game-mode
// gates, win conditions and turn order. PURE: no Firebase imports.

// ── Role Distribution ──

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
  return table[playerCount] || null;
}

// ── Shuffle (Fisher-Yates) ──

function shuffle(array) {
  const arr = [...array];
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

// ── Win Condition Logic ──
// Only Treachery-mode games have automatic team wins. Life Tracker /
// Planechase-only (null roles) must never auto-finish via role heuristics.

const TREACHERY_MODES = new Set(["treachery", "treachery_planechase"]);

function isTreacheryMode(gameMode) {
  // Default missing mode to treachery for legacy games that used roles.
  return gameMode == null || TREACHERY_MODES.has(gameMode);
}

const PLANECHASE_MODES = new Set(["planechase", "treachery_planechase"]);

function isPlanechaseMode(gameMode) {
  return PLANECHASE_MODES.has(gameMode);
}

function checkWinConditions(players, gameMode) {
  if (!isTreacheryMode(gameMode)) {
    return null;
  }

  const alive = players.filter((p) => !p.is_eliminated);

  // Traitor solo win: last player standing is a traitor
  if (alive.length === 1 && alive[0].role === "traitor") {
    return "traitor";
  }

  const leaderAlive = alive.some((p) => p.role === "leader");
  const assassinAlive = alive.some((p) => p.role === "assassin");
  const traitorAlive = alive.some((p) => p.role === "traitor");

  // Assassin wins: Leader eliminated AND at least 1 assassin survives
  if (!leaderAlive && assassinAlive) {
    return "assassin";
  }

  // Leader/Guardian wins: Leader alive + all assassins AND traitors eliminated
  if (leaderAlive && !assassinAlive && !traitorAlive) {
    return "leader";
  }

  // Edge: Leader dead + no assassins + no traitors → assassins credited
  if (!leaderAlive && !assassinAlive && !traitorAlive) {
    return "assassin";
  }

  return null; // Game continues
}

/** Next living seat after `currentId` (order_id order). Unset current → first living. */
function nextLivingPlayerId(seats, currentId) {
  const alive = seats.filter((p) => !p.is_eliminated);
  if (alive.length === 0) return null;
  const currentIndex = seats.findIndex((p) => p.id === currentId);
  for (let step = 1; step <= seats.length; step++) {
    const candidate = seats[(currentIndex + step + seats.length) % seats.length];
    if (!candidate.is_eliminated) return candidate.id;
  }
  return alive[0].id;
}

module.exports = {
  getRoleDistribution,
  shuffle,
  isTreacheryMode,
  isPlanechaseMode,
  checkWinConditions,
  nextLivingPlayerId,
};
