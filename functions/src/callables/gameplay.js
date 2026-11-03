// In-progress gameplay callables: life totals, forfeits, unveiling and the
// host-declared end of a game.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { callableOptions } = require("../config");
const { db, FieldValue } = require("../firebase");
const { checkWinConditions, nextLivingPlayerId } = require("../rules");
const { notifyPlayers } = require("../notifications");

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

    // Clear is_face_down too: a Puppet Master / Metamorph swap turns the
    // card face-down, and unveiling reveals whatever the player NOW holds.
    tx.update(playerDoc.ref, { is_unveiled: true, is_face_down: false });
    tx.update(gameRef, { last_activity_at: FieldValue.serverTimestamp() });

    return { success: true };
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
