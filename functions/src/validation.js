// Validators and sanitisers for untrusted values: callable payloads and
// client-written document fields. PURE: no Firebase imports.

const { RARITY_ORDER } = require("./config");

function isValidRarity(value) {
  return (
    typeof value === "string" &&
    Object.prototype.hasOwnProperty.call(RARITY_ORDER, value)
  );
}

// Sanitize commander names before using them as Firestore map field keys.
// Dots fragment nested paths; `/ ~ * [ ]` are illegal field-path characters.
function sanitizeCommanderKey(name) {
  if (typeof name !== "string") return null;
  const cleaned = name
    .trim()
    .replace(/[.[\]*/~\\]/g, "_")
    .replace(/\s+/g, " ")
    .slice(0, 80);
  return cleaned.length > 0 ? cleaned : null;
}

// ── Numeric Argument Validation ──
// Callable payloads are untrusted. `Number("abc")` is NaN and every
// comparison against NaN is false, so a bare `if (n < 2 || n > 8) throw`
// lets NaN — and non-integers like 5.5 — straight through into Firestore.
// Returns the coerced integer, or null when the value is not one (or falls
// outside an optional inclusive range).

function parseIntegerArg(value, { min, max } = {}) {
  let num = value;
  if (typeof num === "string") {
    // Blank strings coerce to 0, which would silently pass a range check.
    if (num.trim() === "") return null;
    num = Number(num);
  }
  // Number.isInteger already rejects NaN and ±Infinity.
  if (typeof num !== "number" || !Number.isInteger(num)) return null;
  if (min !== undefined && num < min) return null;
  if (max !== undefined && num > max) return null;
  return num;
}

// ── Starting Life ──
// 20 to 60 in steps of 5: every value the create screens (iOS, web, Android)
// offer. The lobby's quick-pick chips are a subset. createGame and
// updateGameSettings both validate through this, and firestore.rules
// (isValidStartingLife) accepts the same set for direct client writes.
// Returns the coerced integer, or null when the value is not one of those.

function parseStartingLife(value) {
  const life = parseIntegerArg(value, { min: 20, max: 60 });
  return life !== null && life % 5 === 0 ? life : null;
}

module.exports = {
  isValidRarity,
  sanitizeCommanderKey,
  parseIntegerArg,
  parseStartingLife,
};
