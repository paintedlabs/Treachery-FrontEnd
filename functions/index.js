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

function getCardsForRole(role) {
  return CARDS.filter((c) => c.role === role);
}

function getCard(id) {
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
  return table[playerCount] || { leaders: 1, guardians: 0, assassins: 2, traitors: 1 };
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

function checkWinConditions(players) {
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

// ── FCM Notification Helper ──

/**
 * Sends a push notification to all players in a game (except the excluded user).
 * Silently skips users without FCM tokens or invalid tokens.
 */
async function notifyPlayers(gameId, excludeUserId, title, body) {
  try {
    // Get player user IDs from the game
    const playersSnap = await db.collection(`games/${gameId}/players`).get();
    const userIds = playersSnap.docs
      .map((d) => d.data().user_id)
      .filter((uid) => uid !== excludeUserId);

    if (userIds.length === 0) return;

    // Fetch FCM tokens from user documents
    const tokens = [];
    // Firestore 'in' queries limited to 30
    for (let i = 0; i < userIds.length; i += 30) {
      const chunk = userIds.slice(i, i + 30);
      const usersSnap = await db
        .collection("users")
        .where("__name__", "in", chunk)
        .get();
      for (const doc of usersSnap.docs) {
        const fcmToken = doc.data().fcm_token;
        if (fcmToken) tokens.push(fcmToken);
      }
    }

    if (tokens.length === 0) return;

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

    // Clean up invalid tokens
    if (response.failureCount > 0) {
      const invalidTokens = [];
      response.responses.forEach((resp, idx) => {
        if (
          resp.error &&
          (resp.error.code === "messaging/invalid-registration-token" ||
            resp.error.code === "messaging/registration-token-not-registered")
        ) {
          invalidTokens.push(tokens[idx]);
        }
      });
      // Remove invalid tokens from user docs
      if (invalidTokens.length > 0) {
        const batch = db.batch();
        for (const token of invalidTokens) {
          const usersWithToken = await db
            .collection("users")
            .where("fcm_token", "==", token)
            .get();
          usersWithToken.docs.forEach((doc) => {
            batch.update(doc.ref, { fcm_token: FieldValue.delete() });
          });
        }
        await batch.commit();
      }
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

  await db.doc(`users/${uid}`).update({ fcm_token: token });

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

    if (includesTreachery) {
      // Validate minimum player count against role distribution
      if (players.length < 1) {
        throw new HttpsError("failed-precondition", "Not enough players.");
      }

      // Build and shuffle roles
      const dist = getRoleDistribution(players.length);
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
        const availableCards = getCardsForRole(role).filter(
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

    tx.update(gameRef, {
      last_activity_at: FieldValue.serverTimestamp(),
    });

    // If eliminated, check win conditions using the already-read players
    let winner = null;
    if (eliminated) {
      const allPlayers = allPlayersSnap.docs.map((d) => {
        const data = d.data();
        if (d.id === playerId) {
          return { ...data, is_eliminated: true, life_total: 0 };
        }
        return data;
      });

      winner = checkWinConditions(allPlayers);
      if (winner) {
        tx.update(gameRef, {
          state: "finished",
          winning_team: winner,
        });
      }
    }

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

    // Update activity timestamp
    tx.update(gameRef, {
      last_activity_at: FieldValue.serverTimestamp(),
    });

    // Check win conditions with updated state
    const updatedPlayers = allPlayers.map((p) => {
      if (p.id === callerPlayer.id) {
        return { ...p, is_eliminated: true, life_total: 0 };
      }
      return p;
    });

    const winner = checkWinConditions(updatedPlayers);
    if (winner) {
      tx.update(gameRef, {
        state: "finished",
        winning_team: winner,
      });
    }

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

    if (game.host_id === uid) {
      // Host is leaving
      const remainingPlayers = allPlayers.filter((p) => p.user_id !== uid);

      if (remainingPlayers.length === 0) {
        // No one left — delete the game
        tx.delete(gameRef);
        return { action: "deleted" };
      } else {
        // Promote the next player (first by order_id)
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

  const gameRef = db.doc(`games/${gameId}`);
  const gameSnap = await gameRef.get();

  if (!gameSnap.exists) throw new HttpsError("not-found", "Game not found.");
  const game = gameSnap.data();

  if (game.state !== "in_progress") {
    throw new HttpsError("failed-precondition", "Game is not in progress.");
  }

  // Find caller's player doc
  const playersSnap = await db
    .collection(`games/${gameId}/players`)
    .where("user_id", "==", uid)
    .limit(1)
    .get();

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

  await playerDoc.ref.update({ is_unveiled: true });

  // Update activity timestamp
  await gameRef.update({ last_activity_at: FieldValue.serverTimestamp() });

  return { success: true };
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

  return db.runTransaction(async (tx) => {
    const gameRef = db.doc(`games/${gameId}`);
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", "Game not found.");
    const game = gameSnap.data();

    if (game.state !== "in_progress")
      throw new HttpsError("failed-precondition", "Game is not in progress.");
    if (!(game.player_ids || []).includes(uid))
      throw new HttpsError("permission-denied", "You are not in this game.");

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
    let result;
    let newPlaneId = planechase.current_plane_id || null;
    let usedPlaneIds = planechase.used_plane_ids || [];

    if (roll < 4) {
      result = "blank";
    } else if (roll === 4) {
      result = "chaos";
    } else {
      result = "planeswalk";

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
    if (planechase.chaotic_aether_active && result === "blank") {
      result = "chaos";
    }

    const updateData = {
      "planechase.last_die_roller_id": uid,
      "planechase.die_roll_count": rollCount,
      "planechase.current_plane_id": newPlaneId,
      "planechase.used_plane_ids": usedPlaneIds,
      last_activity_at: FieldValue.serverTimestamp(),
    };

    // Planeswalking resets Chaotic Aether and clears Spatial Merging
    if (result === "planeswalk") {
      updateData["planechase.chaotic_aether_active"] = false;
      updateData["planechase.secondary_plane_id"] = null;
    }

    tx.update(gameRef, updateData);

    return { result, manaCost, newPlaneId };
  });
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

    if (game.state !== "in_progress")
      throw new HttpsError("failed-precondition", "Game is not in progress.");

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

      // Do NOT update game state — wait for selectPlane call
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

    if (game.state !== "in_progress")
      throw new HttpsError("failed-precondition", "Game is not in progress.");
    if (!(game.player_ids || []).includes(uid))
      throw new HttpsError("permission-denied", "You are not in this game.");

    // Validate the chosen plane exists and is not a phenomenon
    const chosenPlane = PLANE_CARDS.find((p) => p.id === planeId);
    if (!chosenPlane)
      throw new HttpsError("invalid-argument", "Invalid plane ID.");
    if (chosenPlane.is_phenomenon)
      throw new HttpsError("invalid-argument", "Cannot select a phenomenon.");

    const planechase = game.planechase || {};
    let usedPlaneIds = planechase.used_plane_ids || [];
    usedPlaneIds = [...usedPlaneIds, planeId];

    tx.update(gameRef, {
      "planechase.current_plane_id": planeId,
      "planechase.used_plane_ids": usedPlaneIds,
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
      update.winner_user_ids = winnerUserIds;
    }
    tx.update(gameRef, update);

    return { action: "ended" };
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

  if (game.game_mode === "treachery" || game.game_mode === "treachery_planechase") {
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

  // Build a map of userId -> commanderName for deck stats
  const playerCommanders = {};
  for (const p of players) {
    if (p.commander_name) {
      playerCommanders[p.user_id] = p.commander_name;
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
