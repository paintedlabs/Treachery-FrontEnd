// Planechase callables: the planar die, phenomenon resolution and the
// Interplanar Tunnel choice.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const {
  callableOptions,
  CHAOTIC_AETHER_ID,
  INTERPLANAR_TUNNEL_ID,
  SPATIAL_MERGING_ID,
} = require("../config");
const { db, FieldValue } = require("../firebase");
const { shuffle } = require("../rules");
const {
  PLANE_CARDS,
  getPlaneCard,
  parseChaosAbility,
  categorizeChaosAbility,
} = require("../cards");
const { assertPlanechasePlay, assertCallerNotEliminated } = require("../guards");
const { notifyPlayers } = require("../notifications");

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
    await assertCallerNotEliminated(tx, gameId, uid);

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
    await assertCallerNotEliminated(tx, gameId, uid);

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
    // Same guard as rollPlanarDie/resolvePhenomenon. No deadlock risk for a
    // pending Tunnel: any alive seated player can complete the selection.
    await assertCallerNotEliminated(tx, gameId, uid);

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
