// Turn-marker and seating-order callables.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { callableOptions } = require("../config");
const { db, FieldValue } = require("../firebase");
const { nextLivingPlayerId } = require("../rules");

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
