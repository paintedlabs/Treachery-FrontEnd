// Caller / game-state guards shared by callables. NOT pure: they throw
// HttpsError, and assertCallerNotEliminated reads Firestore inside the
// caller's transaction.

const { HttpsError } = require("firebase-functions/v2/https");
const { db } = require("./firebase");
const { isPlanechaseMode } = require("./rules");

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

/**
 * Rejects eliminated callers. assertSeatedInGame only proves membership via
 * player_ids (eliminated players stay seated so they can spectate); the
 * is_eliminated flag lives on the caller's player doc, hence the extra
 * transaction read. Mirrors the caller guard on the traitor ability resolvers.
 */
async function assertCallerNotEliminated(tx, gameId, uid) {
  const seatSnap = await tx.get(
    db.collection(`games/${gameId}/players`).where("user_id", "==", uid).limit(1)
  );
  if (seatSnap.empty) {
    throw new HttpsError("not-found", "You are not in this game.");
  }
  if (seatSnap.docs[0].data().is_eliminated) {
    throw new HttpsError("failed-precondition", "Eliminated players cannot take Planechase actions.");
  }
}

module.exports = {
  assertPlanechasePlay,
  assertCallerNotEliminated,
};
