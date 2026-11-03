// Identity-card and plane-card data access, plus chaos-ability parsing.
// PURE: reads the bundled JSON decks; no Firebase imports.

const { RARITY_ORDER } = require("./config");
const { isValidRarity } = require("./validation");

// ── Identity Cards (embedded so server doesn't depend on client assets) ──

const CARDS = require("../identityCards.json");

// ── Plane Cards (for Planechase game mode) ──

const PLANE_CARDS = require("../planeCards.json");

function getPlaneCard(id) {
  return PLANE_CARDS.find((p) => p.id === id);
}

// ── Chaos Ability Parsing ──
// Extracts chaos ability text from plane card oracle_text.
// Handles three formats:
//   1. "Whenever chaos ensues, <effect>"   (most planes)
//   2. "When chaos ensues, <effect>"        (Bad Wolf Bay, Pompeii, etc.)
//   3. "Chaos: <effect>"                    (Bicycle Rack, Stroopwafel Cafe, etc.)

function parseChaosAbility(oracleText) {
  if (!oracleText) return null;

  // Pattern 1: "Whenever chaos ensues, <effect>"
  const wheneverMatch = oracleText.match(
    /Whenever [Cc]haos ensues,\s*([\s\S]*?)(?:\n(?!.*chaos)|$)/i
  );
  if (wheneverMatch) return wheneverMatch[1].trim();

  // Pattern 2: "When chaos ensues, <effect>" (no "ever")
  const whenMatch = oracleText.match(
    /When chaos ensues,\s*([\s\S]*?)(?:\n(?!.*chaos)|$)/i
  );
  if (whenMatch) return whenMatch[1].trim();

  // Pattern 3: "Chaos: <effect>"
  const colonMatch = oracleText.match(/Chaos:\s*([\s\S]*?)(?:\n|$)/i);
  if (colonMatch) return colonMatch[1].trim();

  // Special case: chaos ensues referenced but not as a standard trigger
  if (/chaos ensues/i.test(oracleText)) {
    const lines = oracleText.split("\n");
    const chaosLine = lines.find((l) => /chaos ensues/i.test(l));
    return chaosLine ? chaosLine.trim() : null;
  }

  return null;
}

// Categorize a chaos ability for game-mechanical display purposes
function categorizeChaosAbility(abilityText) {
  if (!abilityText) return "none";
  const lower = abilityText.toLowerCase();

  if (/deals?\s+\d+\s+damage/i.test(lower) || /loses?\s+\d+\s+life/i.test(lower))
    return "damage";
  if (/gains?\s+\d*\s*life/i.test(lower) || /gain\s+(three|two|one|\d+)\s+life/i.test(lower))
    return "life_gain";
  if (/draw/i.test(lower)) return "draw";
  if (/destroy/i.test(lower) || /exile/i.test(lower)) return "removal";
  if (/create/i.test(lower) && /token/i.test(lower)) return "tokens";
  if (/counter/i.test(lower)) return "counters";
  if (/planeswalk/i.test(lower)) return "planeswalk";
  if (/discard/i.test(lower)) return "discard";
  return "other";
}

function getCardsForRole(role) {
  return CARDS.filter((c) => c.role === role);
}

// Traitor pool under a game's max_traitor_rarity cap (tiers: RARITY_ORDER in
// config.js).
function getTraitorPool(maxRarity) {
  const traitors = getCardsForRole("traitor");
  if (!isValidRarity(maxRarity)) return traitors;
  const cap = RARITY_ORDER[maxRarity];
  return traitors.filter((c) => RARITY_ORDER[c.rarity] <= cap);
}

function _getCard(id) {
  return CARDS.find((c) => c.id === id);
}

module.exports = {
  CARDS,
  PLANE_CARDS,
  getPlaneCard,
  parseChaosAbility,
  categorizeChaosAbility,
  getCardsForRole,
  getTraitorPool,
  _getCard,
};
