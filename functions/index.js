const { onCall, HttpsError } = require("firebase-functions/v2/https");

// CORS config for onCall functions (required for v2 when called from web)
const callableOptions = { cors: true };
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

// ── Identity Cards (embedded so server doesn't depend on client assets) ──

const CARDS = require("./identityCards.json");

// ── Plane Cards (for Planechase game mode) ──

const PLANE_CARDS = require("./planeCards.json");

// Phenomenon IDs with custom resolution behavior
const CHAOTIC_AETHER_ID = "6dc67a65-31bf-4535-9e02-8f6d6ecefde5";
const INTERPLANAR_TUNNEL_ID = "7812174b-2dc1-43e8-b98f-639905e20ab7";
const SPATIAL_MERGING_ID = "aa166578-b13b-4adb-a78e-d5183e987112";

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

// ── Traitor Rarity Cap ──
// Escalating tiers; "special" marks the four table-warping traitors
// (Metamorph, Puppet Master, Treacherous Masochist, Wearer of Masks).
// A game's max_traitor_rarity caps which traitor identities can be
// randomly assigned in startGame; absent/unknown values mean no cap.

const RARITY_ORDER = { uncommon: 1, rare: 2, mythic: 3, special: 4 };

function isValidRarity(value) {
  return (
    typeof value === "string" &&
    Object.prototype.hasOwnProperty.call(RARITY_ORDER, value)
  );
}

function getTraitorPool(maxRarity) {
  const traitors = getCardsForRole("traitor");
  if (!isValidRarity(maxRarity)) return traitors;
  const cap = RARITY_ORDER[maxRarity];
  return traitors.filter((c) => RARITY_ORDER[c.rarity] <= cap);
}

function _getCard(id) {
  return CARDS.find((c) => c.id === id);
}

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

function assertSeatedInGame(game, uid) {
  if (!(game.player_ids || []).includes(uid)) {
    throw new HttpsError("permission-denied", "You are not in this game.");
  }
}

function assertPlanechasePlay(game, uid) {
  if (game.state !== "in_progress") {
    throw new HttpsError("failed-precondition", "Game is not in progress.");
  }
  if (!isPlanechaseMode(game.game_mode)) {
    throw new HttpsError("failed-precondition", "This game is not Planechase.");
  }
  assertSeatedInGame(game, uid);
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

// Characters allowed in join codes (no ambiguous I/O/0/1)
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function generateJoinCode() {
  let code = "";
  for (let i = 0; i < 4; i++) {
    code += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  }
  return code;
}

async function allocateUniqueJoinCode() {
  for (let attempt = 0; attempt < 12; attempt++) {
    const code = generateJoinCode();
    // eslint-disable-next-line no-await-in-loop
    const existing = await db
      .collection("games")
      .where("code", "==", code)
      .limit(1)
      .get();
    if (existing.empty) return code;
  }
  throw new HttpsError("resource-exhausted", "Could not allocate a unique game code.");
}

/** Owner-only private profile path (email / phone / FCM). */
function privateUserRef(uid) {
  return db.doc(`users/${uid}/private/data`);
}

/**
 * Resolves FCM tokens for several users at once, index-aligned with `uids`
 * (null where the user has no token). Batched: one getAll for the private
 * docs, plus a second only for the users whose token has not migrated yet.
 * `uids` must be free of duplicates — getAll resolves responses by path.
 */
async function getUserFcmTokens(uids) {
  if (uids.length === 0) return [];

  const privateSnaps = await db.getAll(...uids.map((uid) => privateUserRef(uid)));
  const tokens = privateSnaps.map((snap) =>
    snap.exists ? snap.data()?.fcm_token || null : null
  );

  // Legacy: token still living on the public user doc
  const legacyIndexes = tokens
    .map((token, idx) => (token ? -1 : idx))
    .filter((idx) => idx >= 0);
  if (legacyIndexes.length > 0) {
    const publicSnaps = await db.getAll(
      ...legacyIndexes.map((idx) => db.doc(`users/${uids[idx]}`))
    );
    publicSnaps.forEach((snap, n) => {
      tokens[legacyIndexes[n]] = snap.exists ? snap.data()?.fcm_token || null : null;
    });
  }

  return tokens;
}

// ── FCM Notification Helper ──

/**
 * Sends a push notification to all players in a game (except the excluded user).
 * Silently skips users without FCM tokens or invalid tokens.
 */
async function notifyPlayers(gameId, excludeUserId, title, body) {
  try {
    // Get player user IDs from the game. Deduped and blank-filtered because
    // the batched read below needs distinct, well-formed document paths.
    const playersSnap = await db.collection(`games/${gameId}/players`).get();
    const userIds = [
      ...new Set(
        playersSnap.docs
          .map((d) => d.data().user_id)
          .filter((uid) => uid && uid !== excludeUserId)
      ),
    ];

    if (userIds.length === 0) return;

    // Fetch FCM tokens from private (or legacy public) user data.
    // tokenEntries stays index-aligned with the tokens sent below, which the
    // invalid-token cleanup relies on to map a failure back to its user.
    const fcmTokens = await getUserFcmTokens(userIds);
    const tokenEntries = []; // { uid, token }
    userIds.forEach((uid, idx) => {
      if (fcmTokens[idx]) tokenEntries.push({ uid, token: fcmTokens[idx] });
    });

    if (tokenEntries.length === 0) return;

    const tokens = tokenEntries.map((e) => e.token);
    const messaging = getMessaging();
    const response = await messaging.sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: { gameId },
      apns: {
        payload: {
          aps: { sound: "default" },
        },
      },
    });

    // Clean up invalid tokens on the user that produced them
    if (response.failureCount > 0) {
      const batch = db.batch();
      let dirty = false;
      response.responses.forEach((resp, idx) => {
        if (
          resp.error &&
          (resp.error.code === "messaging/invalid-registration-token" ||
            resp.error.code === "messaging/registration-token-not-registered")
        ) {
          const { uid } = tokenEntries[idx];
          batch.set(
            privateUserRef(uid),
            { fcm_token: FieldValue.delete() },
            { merge: true }
          );
          batch.set(
            db.doc(`users/${uid}`),
            { fcm_token: FieldValue.delete() },
            { merge: true }
          );
          dirty = true;
        }
      });
      if (dirty) await batch.commit();
    }
  } catch (error) {
    // Non-fatal: notification failure shouldn't break game logic
    console.error("FCM notification error:", error);
  }
}

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: registerFcmToken
// Stores the caller's FCM token on their user document.
// ════════════════════════════════════════════════════════════════

exports.registerFcmToken = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { token } = request.data;
  if (!token || typeof token !== "string") {
    throw new HttpsError("invalid-argument", "token is required.");
  }

  // Store on owner-only private doc; strip any leftover public field.
  await privateUserRef(uid).set({ fcm_token: token }, { merge: true });
  await db.doc(`users/${uid}`).set({ fcm_token: FieldValue.delete() }, { merge: true });

  return { success: true };
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: createGame
// Atomically allocates a unique join code, creates the lobby, and
// seats the host as player 0. Replaces client-side create writes.
// ════════════════════════════════════════════════════════════════

exports.createGame = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const {
    gameMode = "treachery",
    maxPlayers,
    startingLife = 40,
    maxTraitorRarity,
    useOwnDeck = false,
    displayName,
  } = request.data || {};

  const validModes = ["treachery", "planechase", "treachery_planechase", "none"];
  if (!validModes.includes(gameMode)) {
    throw new HttpsError("invalid-argument", "Invalid game mode.");
  }

  const hasTreachery = gameMode === "treachery" || gameMode === "treachery_planechase";
  const hasPlanechase = gameMode === "planechase" || gameMode === "treachery_planechase";
  const defaultMax = 8;
  const mp =
    maxPlayers !== undefined ? parseIntegerArg(maxPlayers, { min: 2, max: 8 }) : defaultMax;
  if (mp === null) {
    throw new HttpsError("invalid-argument", "Max players must be 2-8.");
  }

  const sl = parseIntegerArg(startingLife);
  if (sl === null || ![20, 25, 30, 40, 50].includes(sl)) {
    throw new HttpsError("invalid-argument", "Invalid starting life value.");
  }

  if (maxTraitorRarity !== undefined && !isValidRarity(maxTraitorRarity)) {
    throw new HttpsError("invalid-argument", "Invalid max traitor rarity.");
  }

  // Resolve display name from arg or user profile
  let hostName = typeof displayName === "string" && displayName.trim() ? displayName.trim() : null;
  if (!hostName) {
    const userSnap = await db.doc(`users/${uid}`).get();
    hostName = userSnap.exists ? userSnap.data().display_name || "Host" : "Host";
  }

  const code = await allocateUniqueJoinCode();
  const gameRef = db.collection("games").doc();
  const playerRef = gameRef.collection("players").doc();

  const gameDoc = {
    code,
    host_id: uid,
    state: "waiting",
    max_players: mp,
    starting_life: sl,
    player_ids: [uid],
    game_mode: gameMode,
    created_at: FieldValue.serverTimestamp(),
    last_activity_at: FieldValue.serverTimestamp(),
  };
  if (hasTreachery && maxTraitorRarity !== undefined) {
    gameDoc.max_traitor_rarity = maxTraitorRarity;
  }
  if (hasPlanechase) {
    gameDoc.planechase = {
      use_own_deck: !!useOwnDeck,
      current_plane_id: null,
      used_plane_ids: [],
      last_die_roller_id: null,
      die_roll_count: 0,
    };
  }

  const batch = db.batch();
  batch.set(gameRef, gameDoc);
  batch.set(playerRef, {
    user_id: uid,
    display_name: hostName,
    order_id: 0,
    role: null,
    identity_card_id: null,
    life_total: sl,
    is_eliminated: false,
    is_unveiled: false,
    joined_at: FieldValue.serverTimestamp(),
  });
  await batch.commit();

  return { gameId: gameRef.id, code };
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: acceptFriendRequest
// Recipient accepts a pending request; both friend_ids lists updated.
// Cross-user friend_ids writes are intentionally denied by rules.
// ════════════════════════════════════════════════════════════════

exports.acceptFriendRequest = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { requestId } = request.data || {};
  if (!requestId || typeof requestId !== "string") {
    throw new HttpsError("invalid-argument", "requestId is required.");
  }

  const requestRef = db.doc(`friend_requests/${requestId}`);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(requestRef);
    if (!snap.exists) throw new HttpsError("not-found", "Friend request not found.");
    const fr = snap.data();

    if (fr.to_user_id !== uid) {
      throw new HttpsError("permission-denied", "Only the recipient can accept.");
    }
    if (fr.status !== "pending") {
      throw new HttpsError("failed-precondition", "Request is not pending.");
    }

    const fromId = fr.from_user_id;
    const fromRef = db.doc(`users/${fromId}`);
    const toRef = db.doc(`users/${uid}`);
    const fromSnap = await tx.get(fromRef);
    const toSnap = await tx.get(toRef);
    if (!fromSnap.exists || !toSnap.exists) {
      throw new HttpsError("not-found", "User profile not found.");
    }

    tx.update(requestRef, { status: "accepted" });
    tx.update(fromRef, { friend_ids: FieldValue.arrayUnion(uid) });
    tx.update(toRef, { friend_ids: FieldValue.arrayUnion(fromId) });
    return { success: true };
  });
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: removeFriend
// Mutual remove — both users' friend_ids lists.
// ════════════════════════════════════════════════════════════════

exports.removeFriend = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { friendId } = request.data || {};
  if (!friendId || typeof friendId !== "string") {
    throw new HttpsError("invalid-argument", "friendId is required.");
  }
  if (friendId === uid) {
    throw new HttpsError("invalid-argument", "Cannot remove yourself.");
  }

  const batch = db.batch();
  batch.update(db.doc(`users/${uid}`), {
    friend_ids: FieldValue.arrayRemove(friendId),
  });
  batch.update(db.doc(`users/${friendId}`), {
    friend_ids: FieldValue.arrayRemove(uid),
  });
  await batch.commit();
  return { success: true };
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: startGame
// Called by the host to assign roles, cards, and start the game.
// ════════════════════════════════════════════════════════════════

exports.startGame = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { gameId } = request.data;
  if (!gameId) throw new HttpsError("invalid-argument", "gameId is required.");

  // Run in a transaction for atomicity
  const result = await db.runTransaction(async (tx) => {
    const gameRef = db.doc(`games/${gameId}`);
    const gameSnap = await tx.get(gameRef);

    if (!gameSnap.exists) {
      throw new HttpsError("not-found", "Game not found.");
    }

    const game = gameSnap.data();

    // Determine game mode
    const gameMode = game.game_mode || "treachery";
    const includesTreachery = gameMode === "treachery" || gameMode === "treachery_planechase";
    const includesPlanechase = gameMode === "planechase" || gameMode === "treachery_planechase";

    // Validate caller is the host
    if (game.host_id !== uid) {
      throw new HttpsError("permission-denied", "Only the host can start the game.");
    }

    // Validate game state
    if (game.state !== "waiting") {
      throw new HttpsError("failed-precondition", "Game has already started.");
    }

    // Get players
    const playersSnap = await tx.get(
      db.collection(`games/${gameId}/players`).orderBy("order_id")
    );
    const players = playersSnap.docs.map((d) => ({ ref: d.ref, ...d.data() }));

    if (players.length > 8) {
      throw new HttpsError("failed-precondition", "Games support at most 8 players.");
    }

    if (includesTreachery) {
      // Validate minimum player count against role distribution
      if (players.length < 1) {
        throw new HttpsError("failed-precondition", "Not enough players.");
      }

      const dist = getRoleDistribution(players.length);
      if (!dist) {
        throw new HttpsError("failed-precondition", "Unsupported player count.");
      }

      // Test-seed override: when running in the firebase emulator, accept an
      // explicit { user_id -> { role, identityCardId } } map so E2E tests can
      // drive deterministic role/card assignments. Stripped in production
      // because process.env.FUNCTIONS_EMULATOR is only set in the emulator.
      const isEmulator = process.env.FUNCTIONS_EMULATOR === "true";
      const testSeed = isEmulator ? request.data.testSeed : null;

      if (testSeed) {
        if (!testSeed.assignments || typeof testSeed.assignments !== "object") {
          throw new HttpsError("invalid-argument", "testSeed.assignments must be an object.");
        }
        // Validate role counts match the distribution for this player count.
        const counts = { leader: 0, guardian: 0, assassin: 0, traitor: 0 };
        for (const a of Object.values(testSeed.assignments)) {
          if (counts[a.role] === undefined) {
            throw new HttpsError("invalid-argument", `Invalid role: ${a.role}`);
          }
          counts[a.role]++;
        }
        if (
          counts.leader !== dist.leaders ||
          counts.guardian !== dist.guardians ||
          counts.assassin !== dist.assassins ||
          counts.traitor !== dist.traitors
        ) {
          throw new HttpsError(
            "invalid-argument",
            `testSeed role counts ${JSON.stringify(counts)} do not match distribution ${JSON.stringify(dist)} for ${players.length} players.`
          );
        }
        const usedCardIds = new Set();
        for (const player of players) {
          const assignment = testSeed.assignments[player.user_id];
          if (!assignment) {
            throw new HttpsError("invalid-argument", `Missing testSeed assignment for user ${player.user_id}.`);
          }
          const card = _getCard(assignment.identityCardId);
          if (!card) {
            throw new HttpsError("invalid-argument", `Card ${assignment.identityCardId} not found.`);
          }
          if (card.role !== assignment.role) {
            throw new HttpsError(
              "invalid-argument",
              `Card ${card.id} has role ${card.role} but assignment specifies ${assignment.role}.`
            );
          }
          if (usedCardIds.has(card.id)) {
            throw new HttpsError("invalid-argument", `Card ${card.id} assigned to multiple players.`);
          }
          usedCardIds.add(card.id);
          tx.update(player.ref, {
            role: assignment.role,
            identity_card_id: card.id,
            life_total: game.starting_life + (card.life_modifier || 0),
          });
        }
      } else {
        // Build and shuffle roles
        const roles = [];
        for (let i = 0; i < dist.leaders; i++) roles.push("leader");
        for (let i = 0; i < dist.guardians; i++) roles.push("guardian");
        for (let i = 0; i < dist.assassins; i++) roles.push("assassin");
        for (let i = 0; i < dist.traitors; i++) roles.push("traitor");

        const shuffledRoles = shuffle(roles);

        // Assign roles and cards
        const usedCardIds = new Set();

        for (let i = 0; i < players.length; i++) {
          const role = shuffledRoles[i];
          const rolePool =
            role === "traitor"
              ? getTraitorPool(game.max_traitor_rarity)
              : getCardsForRole(role);
          const availableCards = rolePool.filter(
            (c) => !usedCardIds.has(c.id)
          );

          if (availableCards.length === 0) {
            throw new HttpsError("internal", "Not enough identity cards for role: " + role);
          }

          const card = availableCards[Math.floor(Math.random() * availableCards.length)];
          usedCardIds.add(card.id);

          tx.update(players[i].ref, {
            role: role,
            identity_card_id: card.id,
            life_total: game.starting_life + (card.life_modifier || 0),
          });
        }
      }
    } else {
      // Non-treachery modes: just require at least 1 player
      if (players.length < 1) {
        throw new HttpsError("failed-precondition", "Not enough players.");
      }

      // Set life totals (no card life modifiers since there are no identity cards)
      for (let i = 0; i < players.length; i++) {
        tx.update(players[i].ref, {
          life_total: game.starting_life,
        });
      }
    }

    // Planechase setup: pick a random starting plane
    const gameUpdate = {
      state: "in_progress",
      last_activity_at: FieldValue.serverTimestamp(),
      // Turn starts on the first seat. Optional field — clients that don't
      // know about turns ignore it, and a game doc without it simply has no
      // active player highlighted.
      active_player_id: players.length > 0 ? players[0].ref.id : null,
    };

    if (includesPlanechase && !(game.planechase?.use_own_deck)) {
      // Filter out phenomena for the starting plane
      const startablePlanes = PLANE_CARDS.filter((p) => !p.is_phenomenon);
      const startingPlane = startablePlanes[Math.floor(Math.random() * startablePlanes.length)];
      gameUpdate["planechase.current_plane_id"] = startingPlane.id;
      gameUpdate["planechase.used_plane_ids"] = [startingPlane.id];
      gameUpdate["planechase.chaotic_aether_active"] = false;
      gameUpdate["planechase.secondary_plane_id"] = null;
    }

    // Transition game state + update activity timestamp
    tx.update(gameRef, gameUpdate);

    return { success: true };
  });

  // Send push notification to all players (outside transaction)
  await notifyPlayers(gameId, uid, "Game Started!", "The host has started the game. Check your role!");

  return result;
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: adjustLife
// Adjusts a player's life total. If life drops to 0, eliminates
// the player and checks win conditions.
// ════════════════════════════════════════════════════════════════

exports.adjustLife = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { gameId, playerId, amount } = request.data;
  if (!gameId || !playerId || amount === undefined) {
    throw new HttpsError("invalid-argument", "gameId, playerId, and amount are required.");
  }
  if (typeof amount !== "number" || !Number.isInteger(amount)) {
    throw new HttpsError("invalid-argument", "amount must be an integer.");
  }

  const result = await db.runTransaction(async (tx) => {
    const gameRef = db.doc(`games/${gameId}`);
    const playerRef = db.doc(`games/${gameId}/players/${playerId}`);

    // ALL reads must happen before ANY writes in Firestore transactions
    const gameSnap = await tx.get(gameRef);
    const playerSnap = await tx.get(playerRef);
    const allPlayersSnap = await tx.get(
      db.collection(`games/${gameId}/players`).orderBy("order_id")
    );

    if (!gameSnap.exists) throw new HttpsError("not-found", "Game not found.");
    if (!playerSnap.exists) throw new HttpsError("not-found", "Player not found.");

    const game = gameSnap.data();
    const player = playerSnap.data();

    if (game.state !== "in_progress") {
      throw new HttpsError("failed-precondition", "Game is not in progress.");
    }
    if (!(game.player_ids || []).includes(uid)) {
      throw new HttpsError("permission-denied", "You are not in this game.");
    }
    if (player.is_eliminated) {
      throw new HttpsError("failed-precondition", "Player is already eliminated.");
    }

    let newLife = player.life_total + amount;
    const eliminated = newLife <= 0;
    if (eliminated) newLife = 0;

    // Now do all writes
    const playerUpdate = {
      life_total: newLife,
      is_eliminated: eliminated,
    };
    if (eliminated) playerUpdate.is_unveiled = true;
    tx.update(playerRef, playerUpdate);

    const gameUpdate = {
      last_activity_at: FieldValue.serverTimestamp(),
    };

    // If eliminated, check win conditions using the already-read players
    let winner = null;
    if (eliminated) {
      const seats = allPlayersSnap.docs.map((d) => {
        const data = d.data();
        if (d.id === playerId) {
          return { id: d.id, ...data, is_eliminated: true, life_total: 0 };
        }
        return { id: d.id, ...data };
      });

      winner = checkWinConditions(seats, game.game_mode);
      if (winner) {
        gameUpdate.state = "finished";
        gameUpdate.winning_team = winner;
      }
      // Don't leave the turn marker pointing at a corpse.
      if (game.active_player_id === playerId) {
        gameUpdate.active_player_id = nextLivingPlayerId(seats, playerId);
      }
    }

    tx.update(gameRef, gameUpdate);

    return { newLife, eliminated, winner };
  });

  // Send notification if a player was eliminated
  if (result.eliminated) {
    // Get the eliminated player's name
    const playerSnap = await db.doc(`games/${gameId}/players/${playerId}`).get();
    const playerName = playerSnap.data()?.display_name ?? "A player";
    await notifyPlayers(
      gameId,
      null, // notify everyone including the one who adjusted
      "Player Eliminated",
      `${playerName} has been eliminated!`
    );
  }

  return result;
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: eliminatePlayer
// Forfeits (self-eliminates) the calling player and checks
// win conditions.
// ════════════════════════════════════════════════════════════════

exports.eliminatePlayer = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { gameId } = request.data;
  if (!gameId) throw new HttpsError("invalid-argument", "gameId is required.");

  let callerDisplayName = "A player";

  const result = await db.runTransaction(async (tx) => {
    const gameRef = db.doc(`games/${gameId}`);
    const gameSnap = await tx.get(gameRef);

    if (!gameSnap.exists) throw new HttpsError("not-found", "Game not found.");
    const game = gameSnap.data();

    if (game.state !== "in_progress") {
      throw new HttpsError("failed-precondition", "Game is not in progress.");
    }

    // Find caller's player doc
    const playersSnap = await tx.get(
      db.collection(`games/${gameId}/players`).orderBy("order_id")
    );
    const allPlayers = playersSnap.docs.map((d) => ({ ref: d.ref, id: d.id, ...d.data() }));
    const callerPlayer = allPlayers.find((p) => p.user_id === uid);

    if (!callerPlayer) {
      throw new HttpsError("not-found", "You are not in this game.");
    }
    if (callerPlayer.is_eliminated) {
      throw new HttpsError("failed-precondition", "You are already eliminated.");
    }

    callerDisplayName = callerPlayer.display_name || "A player";

    // Eliminate and unveil
    tx.update(callerPlayer.ref, {
      life_total: 0,
      is_eliminated: true,
      is_unveiled: true,
    });

    // Check win conditions with updated state
    const updatedPlayers = allPlayers.map((p) => {
      if (p.id === callerPlayer.id) {
        return { ...p, is_eliminated: true, life_total: 0 };
      }
      return p;
    });

    const gameUpdate = {
      last_activity_at: FieldValue.serverTimestamp(),
    };
    const winner = checkWinConditions(updatedPlayers, game.game_mode);
    if (winner) {
      gameUpdate.state = "finished";
      gameUpdate.winning_team = winner;
    }
    if (game.active_player_id === callerPlayer.id) {
      gameUpdate.active_player_id = nextLivingPlayerId(updatedPlayers, callerPlayer.id);
    }
    tx.update(gameRef, gameUpdate);

    return { success: true };
  });

  // Notify other players
  await notifyPlayers(
    gameId,
    uid,
    "Player Forfeited",
    `${callerDisplayName} has forfeited the game.`
  );

  return result;
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: joinGame
// Atomically adds a player to a waiting lobby. Prevents race
// conditions where two players join simultaneously and exceed
// maxPlayers or get duplicate orderIds.
// ════════════════════════════════════════════════════════════════

exports.joinGame = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { gameCode } = request.data;
  if (!gameCode) throw new HttpsError("invalid-argument", "gameCode is required.");

  // Look up the game by code (outside transaction since query-by-code is safe)
  const gamesSnap = await db
    .collection("games")
    .where("code", "==", gameCode.toUpperCase())
    .limit(1)
    .get();

  if (gamesSnap.empty) {
    throw new HttpsError("not-found", "Game not found. Check the code and try again.");
  }

  const gameId = gamesSnap.docs[0].id;

  return db.runTransaction(async (tx) => {
    const gameRef = db.doc(`games/${gameId}`);
    const gameSnap = await tx.get(gameRef);

    if (!gameSnap.exists) throw new HttpsError("not-found", "Game not found.");
    const game = gameSnap.data();

    if (game.state !== "waiting") {
      throw new HttpsError("failed-precondition", "This game has already started.");
    }

    // Get all current players atomically
    const playersSnap = await tx.get(
      db.collection(`games/${gameId}/players`).orderBy("order_id")
    );
    const existingPlayers = playersSnap.docs.map((d) => ({ id: d.id, ...d.data() }));

    // Check if already in game
    if (existingPlayers.some((p) => p.user_id === uid)) {
      return { action: "already_joined", gameId };
    }

    // Check capacity atomically
    if (existingPlayers.length >= (game.max_players || 8)) {
      throw new HttpsError("failed-precondition", "This game is full.");
    }

    // Get user display name
    const userSnap = await tx.get(db.doc(`users/${uid}`));
    const displayName = userSnap.exists
      ? userSnap.data().display_name || "Player"
      : "Player";

    // Assign orderId safely based on current count
    const orderId = existingPlayers.length;

    // Create player doc
    const playerRef = db.collection(`games/${gameId}/players`).doc();
    tx.set(playerRef, {
      user_id: uid,
      display_name: displayName,
      order_id: orderId,
      role: null,
      identity_card_id: null,
      life_total: game.starting_life || 40,
      is_eliminated: false,
      is_unveiled: false,
      joined_at: FieldValue.serverTimestamp(),
    });

    // Add to player_ids array
    const updatedPlayerIds = [...(game.player_ids || []), uid];
    tx.update(gameRef, {
      player_ids: updatedPlayerIds,
      last_activity_at: FieldValue.serverTimestamp(),
    });

    return { action: "joined", gameId };
  });
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: leaveGame
// Removes the calling player from a waiting lobby. If host
// leaves, promotes the next player to host instead of deleting.
// ════════════════════════════════════════════════════════════════

exports.leaveGame = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { gameId } = request.data;
  if (!gameId) throw new HttpsError("invalid-argument", "gameId is required.");

  return db.runTransaction(async (tx) => {
    const gameRef = db.doc(`games/${gameId}`);
    const gameSnap = await tx.get(gameRef);

    if (!gameSnap.exists) throw new HttpsError("not-found", "Game not found.");
    const game = gameSnap.data();

    if (game.state !== "waiting") {
      throw new HttpsError("failed-precondition", "Can only leave a game in the waiting state.");
    }

    // Find the caller's player doc
    const playersSnap = await tx.get(
      db.collection(`games/${gameId}/players`).orderBy("order_id")
    );
    const allPlayers = playersSnap.docs.map((d) => ({ ref: d.ref, id: d.id, ...d.data() }));
    const callerPlayer = allPlayers.find((p) => p.user_id === uid);

    if (!callerPlayer) {
      throw new HttpsError("not-found", "You are not in this game.");
    }

    // Remove the player doc
    tx.delete(callerPlayer.ref);

    // Remove from player_ids array
    const updatedPlayerIds = (game.player_ids || []).filter((id) => id !== uid);

    // Renumber surviving seats 0..n-1 so the next join (order_id = length)
    // never collides with an existing order_id.
    const remainingPlayers = allPlayers
      .filter((p) => p.user_id !== uid)
      .sort((a, b) => (a.order_id ?? 0) - (b.order_id ?? 0));
    remainingPlayers.forEach((p, index) => {
      if (p.order_id !== index) {
        tx.update(p.ref, { order_id: index });
      }
    });

    if (game.host_id === uid) {
      // Host is leaving
      if (remainingPlayers.length === 0) {
        // No one left — delete the game
        tx.delete(gameRef);
        return { action: "deleted" };
      } else {
        // Promote the next player (first by order_id after renumber)
        const newHost = remainingPlayers[0];
        tx.update(gameRef, {
          host_id: newHost.user_id,
          player_ids: updatedPlayerIds,
          last_activity_at: FieldValue.serverTimestamp(),
        });
        return { action: "promoted", newHostId: newHost.user_id };
      }
    } else {
      // Non-host leaving — just update player_ids
      tx.update(gameRef, {
        player_ids: updatedPlayerIds,
        last_activity_at: FieldValue.serverTimestamp(),
      });
      return { action: "left" };
    }
  });
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: unveilPlayer
// Unveils the calling player's identity.
// ════════════════════════════════════════════════════════════════

exports.unveilPlayer = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { gameId } = request.data;
  if (!gameId) throw new HttpsError("invalid-argument", "gameId is required.");

  return db.runTransaction(async (tx) => {
    const gameRef = db.doc(`games/${gameId}`);
    const gameSnap = await tx.get(gameRef);

    if (!gameSnap.exists) throw new HttpsError("not-found", "Game not found.");
    const game = gameSnap.data();

    if (game.state !== "in_progress") {
      throw new HttpsError("failed-precondition", "Game is not in progress.");
    }

    // Find caller's player doc within the transaction
    const playersSnap = await tx.get(
      db.collection(`games/${gameId}/players`).where("user_id", "==", uid).limit(1)
    );

    if (playersSnap.empty) {
      throw new HttpsError("not-found", "You are not in this game.");
    }

    const playerDoc = playersSnap.docs[0];
    const player = playerDoc.data();

    if (player.is_eliminated) {
      throw new HttpsError("failed-precondition", "Cannot unveil — you are eliminated.");
    }
    if (player.is_unveiled) {
      throw new HttpsError("failed-precondition", "Already unveiled.");
    }
    if (player.role === "leader") {
      throw new HttpsError("failed-precondition", "Leader is always visible.");
    }

    tx.update(playerDoc.ref, { is_unveiled: true });
    tx.update(gameRef, { last_activity_at: FieldValue.serverTimestamp() });

    return { success: true };
  });
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: resolveMetamorph
// The Metamorph (traitor_07): steal an eliminated opponent's
// identity card. Calling player must have just unveiled traitor_07.
// ════════════════════════════════════════════════════════════════

exports.resolveMetamorph = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { gameId, targetPlayerId } = request.data;
  if (!gameId || !targetPlayerId) {
    throw new HttpsError("invalid-argument", "gameId and targetPlayerId are required.");
  }

  return db.runTransaction(async (tx) => {
    const gameRef = db.doc(`games/${gameId}`);
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", "Game not found.");
    const game = gameSnap.data();
    if (game.state !== "in_progress") {
      throw new HttpsError("failed-precondition", "Game is not in progress.");
    }

    const playersSnap = await tx.get(
      db.collection(`games/${gameId}/players`).orderBy("order_id")
    );
    const allPlayers = playersSnap.docs.map((d) => ({ ref: d.ref, id: d.id, ...d.data() }));
    const caller = allPlayers.find((p) => p.user_id === uid);
    const target = allPlayers.find((p) => p.id === targetPlayerId);

    if (!caller) throw new HttpsError("not-found", "You are not in this game.");
    if (!target) throw new HttpsError("not-found", "Target player not found.");
    if (caller.identity_card_id !== "traitor_07") {
      throw new HttpsError("failed-precondition", "Your card is not The Metamorph.");
    }
    // Must have been dealt The Metamorph originally (blocks Wearer-of-Masks escalation)
    if (caller.original_identity_card_id && caller.original_identity_card_id !== "traitor_07") {
      throw new HttpsError("failed-precondition", "Your card is not The Metamorph.");
    }
    if (!caller.is_unveiled) {
      throw new HttpsError("failed-precondition", "You must unveil first.");
    }
    if (caller.is_eliminated) {
      throw new HttpsError("failed-precondition", "Eliminated players cannot resolve abilities.");
    }
    if (caller.ability_resolved) {
      throw new HttpsError("failed-precondition", "This ability has already been resolved.");
    }
    if (!target.is_eliminated) {
      throw new HttpsError("failed-precondition", "Target must be eliminated.");
    }
    if (target.role === "leader") {
      throw new HttpsError("failed-precondition", "Cannot steal a Leader's card.");
    }
    if (!target.identity_card_id) {
      throw new HttpsError("failed-precondition", "Target has no identity to steal.");
    }

    const stolenCardId = target.identity_card_id;
    const stolenRole = target.role;
    const targetCard = _getCard(stolenCardId);
    const isFaceDown = targetCard ? targetCard.role !== "leader" : true;

    // Role follows the stolen card. The Metamorph "gains control of that
    // player's identity card" — they become the stolen identity, with its
    // role. (Pre-validated above that target.role !== 'leader'.)
    // Clear the card from the target so identities stay unique on the table.
    tx.update(caller.ref, {
      original_identity_card_id: caller.original_identity_card_id || caller.identity_card_id,
      original_role: caller.original_role || caller.role,
      identity_card_id: stolenCardId,
      role: stolenRole,
      is_face_down: isFaceDown,
      ability_resolved: true,
    });
    tx.update(target.ref, {
      identity_card_id: null,
    });
    tx.update(gameRef, { last_activity_at: FieldValue.serverTimestamp() });

    return { success: true, newCardId: stolenCardId, isFaceDown };
  });
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: resolvePuppetMaster
// The Puppet Master (traitor_09): redistribute identity cards
// among other players. Non-Leader cards get turned face-down.
// ════════════════════════════════════════════════════════════════

exports.resolvePuppetMaster = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { gameId, redistributions } = request.data;
  if (!gameId || !redistributions || typeof redistributions !== "object") {
    throw new HttpsError("invalid-argument", "gameId and redistributions are required.");
  }

  return db.runTransaction(async (tx) => {
    const gameRef = db.doc(`games/${gameId}`);
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", "Game not found.");
    const game = gameSnap.data();
    if (game.state !== "in_progress") {
      throw new HttpsError("failed-precondition", "Game is not in progress.");
    }

    const playersSnap = await tx.get(
      db.collection(`games/${gameId}/players`).orderBy("order_id")
    );
    const allPlayers = playersSnap.docs.map((d) => ({ ref: d.ref, id: d.id, ...d.data() }));
    const caller = allPlayers.find((p) => p.user_id === uid);

    if (!caller) throw new HttpsError("not-found", "You are not in this game.");
    // Must currently hold traitor_09 AND originally been dealt it (blocks Wearer escalation)
    if (caller.identity_card_id !== "traitor_09") {
      throw new HttpsError("failed-precondition", "Your card is not The Puppet Master.");
    }
    if (caller.original_identity_card_id && caller.original_identity_card_id !== "traitor_09") {
      throw new HttpsError("failed-precondition", "Your card is not The Puppet Master.");
    }
    if (!caller.is_unveiled) {
      throw new HttpsError("failed-precondition", "You must unveil first.");
    }
    if (caller.is_eliminated) {
      throw new HttpsError("failed-precondition", "Eliminated players cannot resolve abilities.");
    }
    if (caller.ability_resolved) {
      throw new HttpsError("failed-precondition", "This ability has already been resolved.");
    }

    const targetIds = Object.keys(redistributions);
    const assignedCardIds = Object.values(redistributions);

    // Reject duplicate assignment early (existing clients/tests expect failed-precondition)
    if (new Set(assignedCardIds).size !== assignedCardIds.length) {
      throw new HttpsError("failed-precondition", "Each card can only be assigned to one player.");
    }

    // Validate each target player
    const targets = [];
    for (const playerId of targetIds) {
      const player = allPlayers.find((p) => p.id === playerId);
      if (!player) throw new HttpsError("not-found", `Player ${playerId} not found.`);
      if (player.id === caller.id) {
        throw new HttpsError("failed-precondition", "Cannot redistribute your own card.");
      }
      if (player.is_eliminated) {
        throw new HttpsError("failed-precondition", `${player.display_name} is eliminated.`);
      }
      targets.push(player);
    }

    // Must be a permutation of the identities those targets currently hold
    // (no minting cards from the rest of the deck / no dropping cards)
    const currentCards = targets.map((p) => p.identity_card_id).filter(Boolean).sort();
    const sortedAssigned = [...assignedCardIds].sort();
    if (
      currentCards.length !== sortedAssigned.length ||
      currentCards.some((c, i) => c !== sortedAssigned[i])
    ) {
      throw new HttpsError(
        "invalid-argument",
        "Redistributions must be a permutation of the selected players' current cards."
      );
    }

    // Apply redistributions
    for (const [playerId, newCardId] of Object.entries(redistributions)) {
      const player = allPlayers.find((p) => p.id === playerId);
      if (newCardId === player.identity_card_id) continue; // No change

      const newCard = _getCard(newCardId);
      if (!newCard) {
        throw new HttpsError("not-found", `Card ${newCardId} not found.`);
      }
      const isFaceDown = newCard.role !== "leader";

      // Role follows the redistributed card. Per the Puppet Master text,
      // "redistribute control of identity cards" transfers the identity
      // itself, including which role the player has for win-detection.
      tx.update(player.ref, {
        original_identity_card_id: player.original_identity_card_id || player.identity_card_id,
        original_role: player.original_role || player.role,
        identity_card_id: newCardId,
        role: newCard.role,
        is_face_down: isFaceDown,
      });
    }

    tx.update(caller.ref, { ability_resolved: true });
    tx.update(gameRef, { last_activity_at: FieldValue.serverTimestamp() });

    return { success: true };
  });
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: resolveWearerOfMasks
// The Wearer of Masks (traitor_13): become a copy of a random
// non-Leader card from outside the game. Stays a Traitor.
// ════════════════════════════════════════════════════════════════

exports.resolveWearerOfMasks = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { gameId, chosenCardId } = request.data;
  if (!gameId) throw new HttpsError("invalid-argument", "gameId is required.");
  // chosenCardId can be null (player declines)
  if (!chosenCardId) return { success: true, declined: true };

  return db.runTransaction(async (tx) => {
    const gameRef = db.doc(`games/${gameId}`);
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", "Game not found.");
    const game = gameSnap.data();
    if (game.state !== "in_progress") {
      throw new HttpsError("failed-precondition", "Game is not in progress.");
    }

    const playersSnap = await tx.get(
      db.collection(`games/${gameId}/players`).orderBy("order_id")
    );
    const allPlayers = playersSnap.docs.map((d) => ({ ref: d.ref, id: d.id, ...d.data() }));
    const caller = allPlayers.find((p) => p.user_id === uid);

    if (!caller) throw new HttpsError("not-found", "You are not in this game.");
    if (caller.identity_card_id !== "traitor_13") {
      throw new HttpsError("failed-precondition", "Your card is not The Wearer of Masks.");
    }
    if (caller.original_identity_card_id && caller.original_identity_card_id !== "traitor_13") {
      throw new HttpsError("failed-precondition", "Your card is not The Wearer of Masks.");
    }
    if (!caller.is_unveiled) {
      throw new HttpsError("failed-precondition", "You must unveil first.");
    }
    if (caller.is_eliminated) {
      throw new HttpsError("failed-precondition", "Eliminated players cannot resolve abilities.");
    }
    if (caller.ability_resolved) {
      throw new HttpsError("failed-precondition", "This ability has already been resolved.");
    }

    // Validate the chosen card exists and is not a Leader
    const chosenCard = _getCard(chosenCardId);
    if (!chosenCard) {
      throw new HttpsError("not-found", "Card not found.");
    }
    if (chosenCard.role === "leader") {
      throw new HttpsError("failed-precondition", "Cannot choose a Leader card.");
    }
    // Callable-backed specialty traitors must not be copyable — becoming
    // traitor_09 would unlock resolvePuppetMaster, etc.
    const BLOCKED_COPY_IDS = new Set([
      "traitor_07", // Metamorph
      "traitor_09", // Puppet Master
      "traitor_13", // Wearer of Masks
    ]);
    if (BLOCKED_COPY_IDS.has(chosenCardId)) {
      throw new HttpsError(
        "failed-precondition",
        "Cannot copy a special-ability Traitor identity."
      );
    }

    // Validate the card is not currently in use by any player
    const usedCardIds = new Set(allPlayers.map((p) => p.identity_card_id).filter(Boolean));
    if (usedCardIds.has(chosenCardId)) {
      throw new HttpsError("failed-precondition", "That card is already in the game.");
    }

    // Role stays traitor — only the card changes
    tx.update(caller.ref, {
      original_identity_card_id: caller.original_identity_card_id || caller.identity_card_id,
      identity_card_id: chosenCardId,
      ability_resolved: true,
    });
    tx.update(gameRef, { last_activity_at: FieldValue.serverTimestamp() });

    return { success: true, newCardId: chosenCardId };
  });
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: rollPlanarDie
// Rolls the planar die for a Planechase game.
// ════════════════════════════════════════════════════════════════

exports.rollPlanarDie = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { gameId } = request.data;
  if (!gameId) throw new HttpsError("invalid-argument", "gameId is required.");

  const result = await db.runTransaction(async (tx) => {
    const gameRef = db.doc(`games/${gameId}`);
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", "Game not found.");
    const game = gameSnap.data();
    assertPlanechasePlay(game, uid);

    const planechase = game.planechase || {};

    // Roll cost tracking
    let rollCount;
    if (planechase.last_die_roller_id === uid) {
      rollCount = (planechase.die_roll_count || 0) + 1;
    } else {
      rollCount = 1;
    }
    const manaCost = Math.max(0, rollCount - 1);

    // Roll: 0-3 blank, 4 chaos, 5 planeswalk
    const roll = Math.floor(Math.random() * 6);
    let dieResult;
    let newPlaneId = planechase.current_plane_id || null;
    let usedPlaneIds = planechase.used_plane_ids || [];

    if (roll < 4) {
      dieResult = "blank";
    } else if (roll === 4) {
      dieResult = "chaos";
    } else {
      dieResult = "planeswalk";

      if (!planechase.use_own_deck) {
        // Pick next plane (including phenomena this time - they get encountered)
        let available = PLANE_CARDS.filter((p) => !usedPlaneIds.includes(p.id));
        if (available.length === 0) {
          // Reset pool, keep current as used
          usedPlaneIds = newPlaneId ? [newPlaneId] : [];
          available = PLANE_CARDS.filter((p) => !usedPlaneIds.includes(p.id));
        }
        const next = available[Math.floor(Math.random() * available.length)];
        newPlaneId = next.id;
        usedPlaneIds = [...usedPlaneIds, next.id];
      }
    }

    // Chaotic Aether: while active, blank rolls become chaos
    if (planechase.chaotic_aether_active && dieResult === "blank") {
      dieResult = "chaos";
    }

    const updateData = {
      "planechase.last_die_roller_id": uid,
      "planechase.die_roll_count": rollCount,
      "planechase.last_die_result": dieResult,
      "planechase.current_plane_id": newPlaneId,
      "planechase.used_plane_ids": usedPlaneIds,
      last_activity_at: FieldValue.serverTimestamp(),
    };

    // Planeswalking resets Chaotic Aether and clears Spatial Merging
    if (dieResult === "planeswalk") {
      updateData["planechase.chaotic_aether_active"] = false;
      updateData["planechase.secondary_plane_id"] = null;
    }

    tx.update(gameRef, updateData);

    // Build response
    const response = { result: dieResult, manaCost, newPlaneId };

    // When chaos ensues, include the chaos ability info so the client
    // can display the effect without needing its own plane card database
    if (dieResult === "chaos") {
      const currentPlane = getPlaneCard(planechase.current_plane_id);
      if (currentPlane) {
        const chaosText = parseChaosAbility(currentPlane.oracle_text);
        response.chaosAbility = {
          planeName: currentPlane.name,
          planeId: currentPlane.id,
          abilityText: chaosText,
          category: categorizeChaosAbility(chaosText),
        };
      }

      // Spatial Merging: if a secondary plane is active, include its chaos too
      const secondaryPlaneId = planechase.secondary_plane_id;
      if (secondaryPlaneId) {
        const secondaryPlane = getPlaneCard(secondaryPlaneId);
        if (secondaryPlane) {
          const secondaryChaosText = parseChaosAbility(secondaryPlane.oracle_text);
          response.secondaryChaosAbility = {
            planeName: secondaryPlane.name,
            planeId: secondaryPlane.id,
            abilityText: secondaryChaosText,
            category: categorizeChaosAbility(secondaryChaosText),
          };
        }
      }
    }

    return response;
  });

  // Send push notifications for chaos and planeswalk results
  if (result.result === "chaos" || result.result === "planeswalk") {
    try {
      const playerSnap = await db
        .collection(`games/${gameId}/players`)
        .where("user_id", "==", uid)
        .limit(1)
        .get();
      const rollerName =
        playerSnap.docs[0]?.data()?.display_name ?? "A player";

      if (result.result === "chaos") {
        const planeName = result.chaosAbility?.planeName ?? "the current plane";
        await notifyPlayers(
          gameId,
          uid,
          "Chaos Ensues!",
          `${rollerName} rolled chaos on ${planeName}.`
        );
      } else {
        const newPlane = getPlaneCard(result.newPlaneId);
        const planeName = newPlane?.name ?? "a new plane";
        await notifyPlayers(
          gameId,
          uid,
          "Planeswalk!",
          `${rollerName} planeswalked to ${planeName}.`
        );
      }
    } catch (e) {
      // Non-critical: don't fail the roll if notification fails
      console.error("Failed to send planechase notification:", e);
    }
  }

  return result;
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: resolvePhenomenon
// When the current plane is a phenomenon, resolves it and moves
// to the next card.
// ════════════════════════════════════════════════════════════════

exports.resolvePhenomenon = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { gameId } = request.data;
  if (!gameId) throw new HttpsError("invalid-argument", "gameId is required.");

  return db.runTransaction(async (tx) => {
    const gameRef = db.doc(`games/${gameId}`);
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", "Game not found.");
    const game = gameSnap.data();
    assertPlanechasePlay(game, uid);

    const planechase = game.planechase || {};
    if (planechase.use_own_deck)
      throw new HttpsError("failed-precondition", "Using own deck.");

    // Verify current plane is a phenomenon
    const currentPlane = PLANE_CARDS.find((p) => p.id === planechase.current_plane_id);
    if (!currentPlane || !currentPlane.is_phenomenon)
      throw new HttpsError("failed-precondition", "Current plane is not a phenomenon.");

    let usedPlaneIds = planechase.used_plane_ids || [];

    // Helper: get available non-phenomenon planes
    function getAvailablePlanes() {
      let pool = PLANE_CARDS.filter(
        (p) => !p.is_phenomenon && !usedPlaneIds.includes(p.id)
      );
      if (pool.length === 0) {
        usedPlaneIds = planechase.current_plane_id ? [planechase.current_plane_id] : [];
        pool = PLANE_CARDS.filter(
          (p) => !p.is_phenomenon && !usedPlaneIds.includes(p.id)
        );
      }
      return pool;
    }

    // Helper: get available cards (including phenomena) for default behavior
    function getAvailableAll() {
      let pool = PLANE_CARDS.filter((p) => !usedPlaneIds.includes(p.id));
      if (pool.length === 0) {
        usedPlaneIds = planechase.current_plane_id ? [planechase.current_plane_id] : [];
        pool = PLANE_CARDS.filter((p) => !usedPlaneIds.includes(p.id));
      }
      return pool;
    }

    // Branch based on phenomenon type
    if (currentPlane.id === CHAOTIC_AETHER_ID) {
      // Chaotic Aether: activate the effect, then resolve to next random plane
      const available = getAvailableAll();
      const next = available[Math.floor(Math.random() * available.length)];
      usedPlaneIds = [...usedPlaneIds, next.id];

      tx.update(gameRef, {
        "planechase.chaotic_aether_active": true,
        "planechase.current_plane_id": next.id,
        "planechase.used_plane_ids": usedPlaneIds,
        last_activity_at: FieldValue.serverTimestamp(),
      });

      return { newPlaneId: next.id, isPhenomenon: next.is_phenomenon };
    } else if (currentPlane.id === INTERPLANAR_TUNNEL_ID) {
      // Interplanar Tunnel: present 5 random non-phenomenon planes for the player to choose
      const available = getAvailablePlanes();
      const shuffled = shuffle(available);
      const options = shuffled.slice(0, Math.min(5, shuffled.length)).map((p) => ({
        id: p.id,
        name: p.name,
      }));

      tx.update(gameRef, {
        "planechase.pending_plane_options": options.map((o) => o.id),
        last_activity_at: FieldValue.serverTimestamp(),
      });

      return { type: "choose", options };
    } else if (currentPlane.id === SPATIAL_MERGING_ID) {
      // Spatial Merging: pick 2 random non-phenomenon planes
      const available = getAvailablePlanes();
      const shuffled = shuffle(available);

      if (shuffled.length < 2) {
        throw new HttpsError("internal", "Not enough planes available for Spatial Merging.");
      }

      const first = shuffled[0];
      const second = shuffled[1];
      usedPlaneIds = [...usedPlaneIds, first.id, second.id];

      tx.update(gameRef, {
        "planechase.current_plane_id": first.id,
        "planechase.secondary_plane_id": second.id,
        "planechase.used_plane_ids": usedPlaneIds,
        last_activity_at: FieldValue.serverTimestamp(),
      });

      return { newPlaneId: first.id, secondaryPlaneId: second.id, isPhenomenon: false };
    } else {
      // Default: pick next random card (same as original behavior)
      const available = getAvailableAll();
      const next = available[Math.floor(Math.random() * available.length)];
      usedPlaneIds = [...usedPlaneIds, next.id];

      tx.update(gameRef, {
        "planechase.current_plane_id": next.id,
        "planechase.used_plane_ids": usedPlaneIds,
        last_activity_at: FieldValue.serverTimestamp(),
      });

      return { newPlaneId: next.id, isPhenomenon: next.is_phenomenon };
    }
  });
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: selectPlane
// Resolves Interplanar Tunnel after the player chooses one of
// the presented planes.
// ════════════════════════════════════════════════════════════════

exports.selectPlane = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { gameId, planeId } = request.data;
  if (!gameId) throw new HttpsError("invalid-argument", "gameId is required.");
  if (!planeId) throw new HttpsError("invalid-argument", "planeId is required.");

  return db.runTransaction(async (tx) => {
    const gameRef = db.doc(`games/${gameId}`);
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", "Game not found.");
    const game = gameSnap.data();
    assertPlanechasePlay(game, uid);

    const planechase = game.planechase || {};
    if (planechase.use_own_deck) {
      throw new HttpsError("failed-precondition", "Using own deck.");
    }
    if (planechase.current_plane_id !== INTERPLANAR_TUNNEL_ID) {
      throw new HttpsError("failed-precondition", "No Interplanar Tunnel to resolve.");
    }
    const pending = planechase.pending_plane_options || [];
    if (!pending.includes(planeId)) {
      throw new HttpsError("invalid-argument", "Plane was not offered.");
    }

    // Validate the chosen plane exists and is not a phenomenon
    const chosenPlane = PLANE_CARDS.find((p) => p.id === planeId);
    if (!chosenPlane)
      throw new HttpsError("invalid-argument", "Invalid plane ID.");
    if (chosenPlane.is_phenomenon)
      throw new HttpsError("invalid-argument", "Cannot select a phenomenon.");

    let usedPlaneIds = planechase.used_plane_ids || [];
    usedPlaneIds = [...usedPlaneIds, planeId];

    tx.update(gameRef, {
      "planechase.current_plane_id": planeId,
      "planechase.used_plane_ids": usedPlaneIds,
      "planechase.pending_plane_options": FieldValue.delete(),
      last_activity_at: FieldValue.serverTimestamp(),
    });

    return { newPlaneId: planeId };
  });
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: endGame
// Ends a game in progress. For non-treachery modes where there
// are no automatic win conditions.
// ════════════════════════════════════════════════════════════════

exports.endGame = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { gameId, winnerUserIds } = request.data;
  if (!gameId) throw new HttpsError("invalid-argument", "gameId is required.");

  return db.runTransaction(async (tx) => {
    const gameRef = db.doc(`games/${gameId}`);
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", "Game not found.");
    const game = gameSnap.data();

    if (game.host_id !== uid)
      throw new HttpsError("permission-denied", "Only the host can end the game.");
    if (game.state !== "in_progress")
      throw new HttpsError("failed-precondition", "Game is not in progress.");

    const update = {
      state: "finished",
      last_activity_at: FieldValue.serverTimestamp(),
    };
    if (winnerUserIds && Array.isArray(winnerUserIds) && winnerUserIds.length > 0) {
      const seated = new Set(game.player_ids || []);
      const unique = [...new Set(winnerUserIds)];
      if (unique.some((id) => typeof id !== "string" || !seated.has(id))) {
        throw new HttpsError("invalid-argument", "Winners must be players in this game.");
      }
      update.winner_user_ids = unique;
    }
    tx.update(gameRef, update);

    return { action: "ended" };
  });
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: updateGameSettings
// Host-only: update game settings (max players, starting life,
// game mode) while game is in waiting state.
// ════════════════════════════════════════════════════════════════

exports.updateGameSettings = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { gameId, maxPlayers, startingLife, gameMode, maxTraitorRarity } = request.data;
  if (!gameId) throw new HttpsError("invalid-argument", "gameId is required.");

  return db.runTransaction(async (tx) => {
    const gameRef = db.doc(`games/${gameId}`);
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", "Game not found.");
    const game = gameSnap.data();

    if (game.host_id !== uid) {
      throw new HttpsError("permission-denied", "Only the host can change settings.");
    }
    if (game.state !== "waiting") {
      throw new HttpsError("failed-precondition", "Cannot change settings after game starts.");
    }

    // All reads must precede all writes inside a Firestore transaction.
    let playersSnap = null;
    if (startingLife !== undefined) {
      playersSnap = await tx.get(db.collection(`games/${gameId}/players`));
    }

    const update = { last_activity_at: FieldValue.serverTimestamp() };

    if (maxPlayers !== undefined) {
      const mp = parseIntegerArg(maxPlayers, { min: 2, max: 8 });
      if (mp === null) throw new HttpsError("invalid-argument", "Max players must be 2-8.");
      const seated = (game.player_ids || []).length;
      if (mp < seated) {
        throw new HttpsError(
          "failed-precondition",
          "Cannot set max players below the current lobby size."
        );
      }
      update.max_players = mp;
    }

    if (startingLife !== undefined) {
      const sl = parseIntegerArg(startingLife);
      if (sl === null || ![20, 25, 30, 40, 50].includes(sl)) {
        throw new HttpsError("invalid-argument", "Invalid starting life value.");
      }
      update.starting_life = sl;
    }

    if (gameMode !== undefined) {
      const validModes = ["treachery", "planechase", "treachery_planechase", "none"];
      if (!validModes.includes(gameMode)) {
        throw new HttpsError("invalid-argument", "Invalid game mode.");
      }
      update.game_mode = gameMode;
    }

    if (maxTraitorRarity !== undefined) {
      if (!isValidRarity(maxTraitorRarity)) {
        throw new HttpsError("invalid-argument", "Invalid max traitor rarity.");
      }
      update.max_traitor_rarity = maxTraitorRarity;
    }

    tx.update(gameRef, update);

    // If starting life changed, update all existing players' life totals.
    // Reuse the already-validated value rather than re-coercing the argument.
    if (startingLife !== undefined && playersSnap) {
      playersSnap.docs.forEach((doc) => {
        tx.update(doc.ref, { life_total: update.starting_life });
      });
    }

    return { success: true };
  });
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: setActivePlayer
// Sets whose turn it is. Any player at the table may set it —
// this is a shared companion app for an in-person game, not an
// enforcement engine, and the same permissiveness already applies
// to adjustLife.
// ════════════════════════════════════════════════════════════════

exports.setActivePlayer = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { gameId, playerId } = request.data;
  if (!gameId) throw new HttpsError("invalid-argument", "gameId is required.");

  return db.runTransaction(async (tx) => {
    const gameRef = db.doc(`games/${gameId}`);
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", "Game not found.");
    const game = gameSnap.data();

    if (game.state !== "in_progress") {
      throw new HttpsError("failed-precondition", "Game is not in progress.");
    }
    if (!(game.player_ids || []).includes(uid)) {
      throw new HttpsError("permission-denied", "You are not in this game.");
    }

    // null clears the turn marker; anything else must be a real player.
    if (playerId !== null && playerId !== undefined) {
      const playerSnap = await tx.get(db.doc(`games/${gameId}/players/${playerId}`));
      if (!playerSnap.exists) throw new HttpsError("not-found", "Player not found.");
      if (playerSnap.data().is_eliminated) {
        throw new HttpsError("failed-precondition", "That player is eliminated.");
      }
    }

    tx.update(gameRef, {
      active_player_id: playerId ?? null,
      last_activity_at: FieldValue.serverTimestamp(),
    });

    return { activePlayerId: playerId ?? null };
  });
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: advanceTurn
// Moves the turn to the next seat, skipping eliminated players.
// ════════════════════════════════════════════════════════════════

exports.advanceTurn = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { gameId } = request.data;
  if (!gameId) throw new HttpsError("invalid-argument", "gameId is required.");

  return db.runTransaction(async (tx) => {
    const gameRef = db.doc(`games/${gameId}`);
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", "Game not found.");
    const game = gameSnap.data();

    if (game.state !== "in_progress") {
      throw new HttpsError("failed-precondition", "Game is not in progress.");
    }
    if (!(game.player_ids || []).includes(uid)) {
      throw new HttpsError("permission-denied", "You are not in this game.");
    }

    const playersSnap = await tx.get(
      db.collection(`games/${gameId}/players`).orderBy("order_id")
    );
    const seats = playersSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
    const nextId = nextLivingPlayerId(seats, game.active_player_id);

    tx.update(gameRef, {
      active_player_id: nextId,
      last_activity_at: FieldValue.serverTimestamp(),
    });

    return { activePlayerId: nextId };
  });
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: reorderSeats
// Rewrites every player's order_id to match a caller-supplied
// seating order — the persistence behind dragging players around
// the table. Runs server-side rather than through security rules
// because the invariant is "the new order is a PERMUTATION of the
// existing seats", which spans documents and rules cannot express.
//
// Side benefit: because it always writes a contiguous 0..N-1 run,
// it also repairs duplicate order_ids if a client ever left the ring
// in a bad state. leaveGame already renumbers survivors.
// ════════════════════════════════════════════════════════════════

exports.reorderSeats = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { gameId, orderedPlayerIds } = request.data;
  if (!gameId) throw new HttpsError("invalid-argument", "gameId is required.");
  if (!Array.isArray(orderedPlayerIds)) {
    throw new HttpsError("invalid-argument", "orderedPlayerIds must be an array.");
  }

  return db.runTransaction(async (tx) => {
    const gameRef = db.doc(`games/${gameId}`);
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", "Game not found.");
    const game = gameSnap.data();

    if (!(game.player_ids || []).includes(uid)) {
      throw new HttpsError("permission-denied", "You are not in this game.");
    }
    if (game.state === "finished") {
      throw new HttpsError("failed-precondition", "Game is already finished.");
    }

    const playersSnap = await tx.get(db.collection(`games/${gameId}/players`));
    const existingIds = playersSnap.docs.map((d) => d.id);

    // Permutation check: same size, no duplicates, exactly the same members.
    // Without this a caller could drop players out of the seating (leaving
    // them with a stale order_id) or smuggle in ids from another game.
    if (orderedPlayerIds.length !== existingIds.length) {
      throw new HttpsError(
        "invalid-argument",
        `Expected ${existingIds.length} seats, got ${orderedPlayerIds.length}.`
      );
    }
    const seen = new Set();
    const existing = new Set(existingIds);
    for (const id of orderedPlayerIds) {
      if (typeof id !== "string") {
        throw new HttpsError("invalid-argument", "Seat ids must be strings.");
      }
      if (seen.has(id)) {
        throw new HttpsError("invalid-argument", `Duplicate seat id: ${id}`);
      }
      if (!existing.has(id)) {
        throw new HttpsError("invalid-argument", `Unknown player id: ${id}`);
      }
      seen.add(id);
    }

    orderedPlayerIds.forEach((playerId, index) => {
      tx.update(db.doc(`games/${gameId}/players/${playerId}`), { order_id: index });
    });
    tx.update(gameRef, { last_activity_at: FieldValue.serverTimestamp() });

    return { success: true, seats: orderedPlayerIds.length };
  });
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: cleanupStaleGames (Scheduled)
// Runs every hour. Deletes games stuck in "waiting" or
// "in_progress" with no activity for 24 hours.
// ════════════════════════════════════════════════════════════════

exports.cleanupStaleGames = onSchedule("every 1 hours", async () => {
  const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000);

  // Find stale games: last_activity_at (or created_at as fallback) older than 24h
  // We query "waiting" and "in_progress" separately since Firestore
  // doesn't support != on state and inequality on timestamp in one query.

  const staleStates = ["waiting", "in_progress"];
  let totalDeleted = 0;

  for (const state of staleStates) {
    // First try games with last_activity_at
    const withActivitySnap = await db
      .collection("games")
      .where("state", "==", state)
      .where("last_activity_at", "<", cutoff)
      .limit(100)
      .get();

    // Also find games without last_activity_at (legacy) using created_at
    const withoutActivitySnap = await db
      .collection("games")
      .where("state", "==", state)
      .where("created_at", "<", cutoff)
      .limit(100)
      .get();

    // Merge, deduplicate
    const gameIds = new Set();
    const gameDocs = [];

    for (const doc of [...withActivitySnap.docs, ...withoutActivitySnap.docs]) {
      if (gameIds.has(doc.id)) continue;
      // Double-check: if it has last_activity_at and it's recent, skip
      const data = doc.data();
      if (data.last_activity_at && data.last_activity_at.toDate() >= cutoff) continue;
      gameIds.add(doc.id);
      gameDocs.push(doc);
    }

    // Delete each stale game and its players subcollection
    for (const gameDoc of gameDocs) {
      const playersSnap = await db
        .collection(`games/${gameDoc.id}/players`)
        .get();

      const batch = db.batch();
      playersSnap.docs.forEach((pDoc) => batch.delete(pDoc.ref));
      batch.delete(gameDoc.ref);
      await batch.commit();
      totalDeleted++;
    }
  }

  console.log(`cleanupStaleGames: deleted ${totalDeleted} stale games.`);
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: onPlayerJoined (Firestore trigger)
// Sends a push notification when a new player joins a lobby.
// ════════════════════════════════════════════════════════════════

const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");

exports.onPlayerJoined = onDocumentCreated(
  "games/{gameId}/players/{playerId}",
  async (event) => {
    const player = event.data?.data();
    if (!player) return;

    const gameId = event.params.gameId;
    const displayName = player.display_name || "Someone";

    // Update last_activity_at on the game
    await db.doc(`games/${gameId}`).update({
      last_activity_at: FieldValue.serverTimestamp(),
    });

    // Notify other players
    await notifyPlayers(
      gameId,
      player.user_id,
      "Player Joined",
      `${displayName} joined the game!`
    );
  }
);

// ════════════════════════════════════════════════════════════════
// FIRESTORE TRIGGER: onGameFinished
// Fires when a game's state transitions to "finished".
// Updates ELO ratings for all players (and per-deck stats).
// ════════════════════════════════════════════════════════════════

exports.onGameFinished = onDocumentUpdated("games/{gameId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  // Only fire on state transition to finished
  if (before.state === "finished" || after.state !== "finished") return;

  const gameId = event.params.gameId;
  const game = after;

  // Fetch all players
  const playersSnap = await db.collection(`games/${gameId}/players`).get();
  const players = playersSnap.docs.map((d) => ({ id: d.id, ...d.data() }));

  if (players.length < 2) return; // Need at least 2 players for ELO

  // Determine winners and losers
  let winnerUserIds = [];
  let loserUserIds = [];

  if (isTreacheryMode(game.game_mode)) {
    // Treachery: use winning_team
    const winningTeam = game.winning_team;
    if (!winningTeam) return;

    for (const player of players) {
      if (!player.role) continue;
      const isWinner =
        (winningTeam === "leader" && (player.role === "leader" || player.role === "guardian")) ||
        (winningTeam === "assassin" && player.role === "assassin") ||
        (winningTeam === "traitor" && player.role === "traitor");
      if (isWinner) {
        winnerUserIds.push(player.user_id);
      } else {
        loserUserIds.push(player.user_id);
      }
    }
  } else {
    // Non-treachery: use winner_user_ids from game doc
    winnerUserIds = game.winner_user_ids || [];
    if (winnerUserIds.length === 0) return; // No winners declared, skip ELO

    loserUserIds = players
      .map((p) => p.user_id)
      .filter((uid) => !winnerUserIds.includes(uid));
  }

  if (winnerUserIds.length === 0 || loserUserIds.length === 0) return;

  // Build a map of userId -> sanitized commanderName for deck stats
  const playerCommanders = {};
  for (const p of players) {
    const key = sanitizeCommanderKey(p.commander_name);
    if (key) {
      playerCommanders[p.user_id] = key;
    }
  }

  // Fetch all user docs
  const allUserIds = [...new Set([...winnerUserIds, ...loserUserIds])];
  const userDocs = {};
  for (const uid of allUserIds) {
    const snap = await db.doc(`users/${uid}`).get();
    if (snap.exists) userDocs[uid] = snap.data();
  }

  // ELO calculation (K=32)
  const K = 32;
  const eloChanges = {};

  for (const uid of allUserIds) {
    eloChanges[uid] = 0;
  }

  // Each winner vs each loser
  for (const winnerId of winnerUserIds) {
    const winnerElo = (userDocs[winnerId]?.elo) || 1500;
    for (const loserId of loserUserIds) {
      const loserElo = (userDocs[loserId]?.elo) || 1500;

      const expectedWinner = 1.0 / (1.0 + Math.pow(10, (loserElo - winnerElo) / 400));
      const expectedLoser = 1.0 / (1.0 + Math.pow(10, (winnerElo - loserElo) / 400));

      eloChanges[winnerId] += K * (1 - expectedWinner);
      eloChanges[loserId] += K * (0 - expectedLoser);
    }
  }

  // Average changes (divide by number of opponents)
  for (const winnerId of winnerUserIds) {
    eloChanges[winnerId] = Math.round(eloChanges[winnerId] / loserUserIds.length);
  }
  for (const loserId of loserUserIds) {
    eloChanges[loserId] = Math.round(eloChanges[loserId] / winnerUserIds.length);
  }

  // Update user docs atomically
  const batch = db.batch();

  for (const uid of allUserIds) {
    const userRef = db.doc(`users/${uid}`);
    const currentElo = (userDocs[uid]?.elo) || 1500;
    const newElo = Math.max(0, currentElo + eloChanges[uid]);
    const isWinner = winnerUserIds.includes(uid);
    const commanderName = playerCommanders[uid];

    const updates = { elo: newElo };

    if (commanderName) {
      const deckStats = userDocs[uid]?.deck_stats || {};
      const currentDeck = deckStats[commanderName] || { elo: 1500, wins: 0, losses: 0, games: 0 };

      // Deck ELO uses same change as player ELO
      const newDeckElo = Math.max(0, currentDeck.elo + eloChanges[uid]);

      updates[`deck_stats.${commanderName}`] = {
        elo: newDeckElo,
        wins: currentDeck.wins + (isWinner ? 1 : 0),
        losses: currentDeck.losses + (isWinner ? 0 : 1),
        games: currentDeck.games + 1,
      };
    }

    batch.update(userRef, updates);
  }

  await batch.commit();
  console.log(`onGameFinished: Updated ELO for ${allUserIds.length} players in game ${gameId}`);
});
