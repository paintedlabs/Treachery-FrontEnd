// Shared constants. PURE: plain data and no requires, so every module
// (and the unit tests) can load it without touching Firebase.

// CORS config for onCall functions (required for v2 when called from web)
const callableOptions = { cors: true };

// ── Traitor Rarity Cap ──
// Escalating tiers; "special" marks the four table-warping traitors
// (Metamorph, Puppet Master, Treacherous Masochist, Wearer of Masks).
// A game's max_traitor_rarity caps which traitor identities can be
// randomly assigned in startGame; absent/unknown values mean no cap.

const RARITY_ORDER = { uncommon: 1, rare: 2, mythic: 3, special: 4 };

// Phenomenon IDs with custom resolution behavior
const CHAOTIC_AETHER_ID = "6dc67a65-31bf-4535-9e02-8f6d6ecefde5";
const INTERPLANAR_TUNNEL_ID = "7812174b-2dc1-43e8-b98f-639905e20ab7";
const SPATIAL_MERGING_ID = "aa166578-b13b-4adb-a78e-d5183e987112";

module.exports = {
  callableOptions,
  RARITY_ORDER,
  CHAOTIC_AETHER_ID,
  INTERPLANAR_TUNNEL_ID,
  SPATIAL_MERGING_ID,
};
