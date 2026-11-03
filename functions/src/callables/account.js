// Account callables: deleteAccount, the in-app account deletion App Store
// Review Guideline 5.1.1(v) requires of any app that lets people sign up.
//
// The order of the steps is the design. Every check that can refuse the
// deletion runs before the first write. Firestore data goes before the Auth
// account, so a run that fails part-way leaves the caller signed in and able
// to retry. Every step is safe to repeat, so a retry finishes whatever a
// failed run left behind.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { callableOptions } = require("../config");
const { db, FieldValue, getAuth } = require("../firebase");
const { leaveWaitingGame } = require("./lobby");

// The clients show this message verbatim.
const GAME_IN_PROGRESS_MESSAGE =
  "You're in a game that's still in progress. You can delete your account once that game ends.";

// Replaces the deleted user's name on their seats in other players' history.
const DELETED_PLAYER_NAME = "Deleted player";

// Upper bound on writes per WriteBatch commit.
const MAX_BATCH_WRITES = 500;

// Upper bound on seat queries in flight at once; step 3 runs one per game.
const MAX_PARALLEL_QUERIES = 50;

// The gRPC status the Firestore Admin SDK reports when a write updates a
// document that does not exist.
const FIRESTORE_NOT_FOUND = 5;

/**
 * Commits `writes` (functions that each add one write to the batch they are
 * handed) in batches of at most MAX_BATCH_WRITES. Each batch is atomic on its
 * own, not together with the others; every write here is idempotent, so a
 * failure part-way is repaired by retrying the whole call.
 */
async function commitInBatches(writes) {
  for (let i = 0; i < writes.length; i += MAX_BATCH_WRITES) {
    const batch = db.batch();
    writes.slice(i, i + MAX_BATCH_WRITES).forEach((write) => write(batch));
    // Deliberate sequential await (no-await-in-loop).
    await batch.commit();
  }
}

/**
 * Runs leaveGame's transaction for one lobby the caller is listed in or
 * hosts. Holding no seat is not an error here: the caller still comes off
 * player_ids, and a seatless host still hands the lobby to the lowest
 * remaining seat (or deletes it when no seat is left). A lobby that has
 * vanished, or no longer lists or is hosted by the caller, holds nothing of
 * theirs. A lobby its host started after the in-progress check is now a
 * live game, which refuses the deletion.
 */
async function leaveLobby(gameId, uid) {
  try {
    await db.runTransaction((tx) => leaveWaitingGame(tx, gameId, uid, { requireSeat: false }));
  } catch (error) {
    if (error instanceof HttpsError && error.code === "not-found") return;
    if (error instanceof HttpsError && error.code === "failed-precondition") {
      throw new HttpsError("failed-precondition", GAME_IN_PROGRESS_MESSAGE);
    }
    throw error;
  }
}

/**
 * The caller's seats (player docs) in `gameIds`, queried at most
 * MAX_PARALLEL_QUERIES games at a time.
 */
async function findSeats(gameIds, uid) {
  const seatRefs = [];
  for (let i = 0; i < gameIds.length; i += MAX_PARALLEL_QUERIES) {
    // Deliberate sequential await (no-await-in-loop).
    const snaps = await Promise.all(
      gameIds
        .slice(i, i + MAX_PARALLEL_QUERIES)
        .map((gameId) =>
          db.collection(`games/${gameId}/players`).where("user_id", "==", uid).get()
        )
    );
    snaps.forEach((snap) => snap.docs.forEach((doc) => seatRefs.push(doc.ref)));
  }
  return seatRefs;
}

/**
 * Drops `uid` from every friend list and deletes every friend request to or
 * from them. Resolves to how many of each this pass found.
 */
async function unlinkSocialData(uid) {
  const [friendsSnap, sentSnap, receivedSnap] = await Promise.all([
    db.collection("users").where("friend_ids", "array-contains", uid).get(),
    db.collection("friend_requests").where("from_user_id", "==", uid).get(),
    db.collection("friend_requests").where("to_user_id", "==", uid).get(),
  ]);
  // Keyed by path: a request the caller sent to themselves matches both
  // queries and is deleted once.
  const requestRefs = new Map(
    [...sentSnap.docs, ...receivedSnap.docs].map((doc) => [doc.ref.path, doc.ref])
  );
  await commitInBatches([
    ...friendsSnap.docs.map((doc) => (batch) =>
      batch.update(doc.ref, { friend_ids: FieldValue.arrayRemove(uid) })
    ),
    ...[...requestRefs.values()].map((ref) => (batch) => batch.delete(ref)),
  ]);
  return { friends: friendsSnap.size, requests: requestRefs.size };
}

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: deleteAccount
// Deletes the caller's account: leaves their waiting lobbies,
// anonymizes their seats in played games, unlinks friends and
// friend requests, deletes the profile, then the sign-in account.
// Refused while the caller is in or hosts a game in progress.
// ════════════════════════════════════════════════════════════════

exports.deleteAccount = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  // Every game the caller is listed in or hosts, keyed by id because a game
  // can match both queries. Single-field queries only, so Firestore's
  // automatic indexes serve them and no composite index has to be deployed
  // first; game state is filtered here instead of in the query.
  const [seatedSnap, hostedSnap] = await Promise.all([
    db.collection("games").where("player_ids", "array-contains", uid).get(),
    db.collection("games").where("host_id", "==", uid).get(),
  ]);
  const games = new Map(
    [...seatedSnap.docs, ...hostedSnap.docs].map((doc) => [doc.id, doc.data()])
  );

  // 1. Refuse during a live game, before anything is written: deleting
  //    mid-game would leave a ghost seat in a game others are still playing.
  //    A game the caller only hosts counts too. startGame does not need the
  //    host to hold a seat, and endGame is host-only, so a live game whose
  //    host is deleted could never be ended.
  if ([...games.values()].some((game) => game.state === "in_progress")) {
    throw new HttpsError("failed-precondition", GAME_IN_PROGRESS_MESSAGE);
  }

  // 2. Leave waiting lobbies with leaveGame's own transaction.
  const lobbyIds = [...games]
    .filter(([, game]) => game.state === "waiting")
    .map(([gameId]) => gameId);
  for (const gameId of lobbyIds) {
    // Deliberate sequential await (no-await-in-loop).
    await leaveLobby(gameId, uid);
  }

  // 3. Anonymize the caller's seats in every game they played or hosted.
  //    user_id, role, life and results stay, so other players' history and
  //    stats remain coherent.
  const seatRefs = await findSeats([...games.keys()], uid);
  await commitInBatches(
    seatRefs.map((ref) => (batch) =>
      batch.update(ref, {
        display_name: DELETED_PLAYER_NAME,
        commander_name: FieldValue.delete(),
      })
    )
  );

  // 4. Unlink social data. A friend who deletes their own account between
  //    this step's queries and its commit fails that batch with NOT_FOUND.
  //    A fresh pass no longer finds them, so one retry finishes the step.
  let social;
  try {
    social = await unlinkSocialData(uid);
  } catch (error) {
    if (error?.code !== FIRESTORE_NOT_FOUND) throw error;
    social = await unlinkSocialData(uid);
  }

  // 5. Delete the profile, including private/* (email, phone, FCM token).
  await db.recursiveDelete(db.doc(`users/${uid}`));

  // 6. Delete the sign-in account last. If this throws, the caller is still
  //    signed in and can retry; an account that is already gone means an
  //    earlier run got this far, which counts as done.
  try {
    await getAuth().deleteUser(uid);
  } catch (error) {
    if (error?.code !== "auth/user-not-found") throw error;
  }

  console.log(
    `deleteAccount: deleted ${uid} (left ${lobbyIds.length} lobbies, ` +
      `anonymized ${seatRefs.length} seats, unlinked ${social.friends} friends, ` +
      `deleted ${social.requests} friend requests)`
  );
  return { success: true };
});
