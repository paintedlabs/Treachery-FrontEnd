// Traitor identity-card abilities: The Metamorph, The Puppet Master and
// The Wearer of Masks.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { callableOptions } = require("../config");
const { db, FieldValue } = require("../firebase");
const { _getCard } = require("../cards");

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
