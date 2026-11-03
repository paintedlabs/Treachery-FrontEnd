// Lobby lifecycle callables: everything that runs while a game is
// "waiting" (create, settings, join, leave) plus the start/deal transition.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { callableOptions } = require("../config");
const { db, FieldValue } = require("../firebase");
const { isValidRarity, parseIntegerArg } = require("../validation");
const { getRoleDistribution, shuffle } = require("../rules");
const { PLANE_CARDS, getCardsForRole, getTraitorPool, _getCard } = require("../cards");
const { notifyPlayers } = require("../notifications");

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
    // Deliberate sequential await (no-await-in-loop).
    const existing = await db
      .collection("games")
      .where("code", "==", code)
      .limit(1)
      .get();
    if (existing.empty) return code;
  }
  throw new HttpsError("resource-exhausted", "Could not allocate a unique game code.");
}

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
            is_unveiled: false,
            is_eliminated: false,
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
            is_unveiled: false,
            is_eliminated: false,
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
          is_unveiled: false,
          is_eliminated: false,
        });
      }
    }

    // Planechase setup: pick a random starting plane
    const gameUpdate = {
      state: "in_progress",
      last_activity_at: FieldValue.serverTimestamp(),
      // Reconcile player_ids to the players actually being dealt in. The
      // append-self rules path lets any signed-in user add their uid to a
      // waiting game's player_ids WITHOUT creating a player doc — invisible
      // to every lobby UI (they all render the subcollection). player_ids
      // gates player-doc reads, so an unreconciled ghost uid would read every
      // role and identity card the moment they exist. Rebuilding the array
      // from the seated players evicts ghosts at exactly the point the data
      // becomes sensitive, while legitimate legacy direct-joins survive
      // (they create a player doc alongside the array append).
      player_ids: [...new Set(players.map((p) => p.user_id).filter(Boolean))],
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
// SHARED: leaveWaitingGame
// The leave-lobby transaction body, shared by leaveGame and
// deleteAccount (callables/account.js) so seat removal, seat
// renumbering and host hand-off have exactly one implementation.
// ════════════════════════════════════════════════════════════════

/**
 * Removes `uid` from the waiting lobby `gameId` inside transaction `tx`:
 * deletes their player doc, renumbers the surviving seats, drops them from
 * player_ids, and promotes the next seat to host (or deletes the game when
 * nobody is left). Resolves to leaveGame's response: { action: "left" },
 * { action: "promoted", newHostId } or { action: "deleted" }. Throws
 * not-found when the game or the caller's seat is missing, and
 * failed-precondition when the game is no longer waiting.
 *
 * With `requireSeat: false` (deleteAccount), a caller who is on player_ids
 * or is the host but holds no seat leaves the same way, minus the seat
 * delete, instead of getting not-found. That way a seatless host still
 * hands the lobby on rather than leaving host_id on an account nobody can
 * start it from. not-found then means the lobby holds nothing of theirs.
 */
async function leaveWaitingGame(tx, gameId, uid, { requireSeat = true } = {}) {
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
    const isMember = game.host_id === uid || (game.player_ids || []).includes(uid);
    if (requireSeat || !isMember) {
      throw new HttpsError("not-found", "You are not in this game.");
    }
  }

  // Remove the player doc
  if (callerPlayer) tx.delete(callerPlayer.ref);

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
}

// Not a deployed function: index.js lists every deployed name explicitly.
exports.leaveWaitingGame = leaveWaitingGame;

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

  return db.runTransaction((tx) => leaveWaitingGame(tx, gameId, uid));
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
