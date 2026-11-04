// Account callables: deleteAccount, the in-app account deletion App Store
// Review Guideline 5.1.1(v) requires of any app that lets people sign up.
// Its steps live in deleteAccountFor, which scripts/delete-account.js also
// runs, for an account whose owner asked by email to have it deleted.
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
 * Every game `uid` is listed in or hosts, as a Map from game id to its data,
 * keyed by id because a game can match both queries. Single-field queries
 * only, so Firestore's automatic indexes serve them and no composite index
 * has to be deployed first; game state is filtered here instead of in the
 * query.
 */
async function findGames(uid) {
  const [seatedSnap, hostedSnap] = await Promise.all([
    db.collection("games").where("player_ids", "array-contains", uid).get(),
    db.collection("games").where("host_id", "==", uid).get(),
  ]);
  return new Map(
    [...seatedSnap.docs, ...hostedSnap.docs].map((doc) => [doc.id, doc.data()])
  );
}

/** The ids of the games in `games` (from findGames) in state `state`. */
function gameIdsInState(games, state) {
  return [...games].filter(([, game]) => game.state === state).map(([gameId]) => gameId);
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
 * The profiles whose friend lists hold `uid`, and every friend request to or
 * from them.
 */
async function findSocialData(uid) {
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
  return {
    friendRefs: friendsSnap.docs.map((doc) => doc.ref),
    requestRefs: [...requestRefs.values()],
  };
}

/**
 * Drops `uid` from every friend list and deletes every friend request to or
 * from them. Resolves to how many of each this pass found.
 */
async function unlinkSocialData(uid) {
  const { friendRefs, requestRefs } = await findSocialData(uid);
  await commitInBatches([
    ...friendRefs.map((ref) => (batch) =>
      batch.update(ref, { friend_ids: FieldValue.arrayRemove(uid) })
    ),
    ...requestRefs.map((ref) => (batch) => batch.delete(ref)),
  ]);
  return { friends: friendRefs.length, requests: requestRefs.length };
}

/**
 * users/{uid} and every document under it that exists: what step 5's
 * recursiveDelete removes. listDocuments also returns documents that don't
 * exist but have subcollections, so documents under those are found too.
 */
async function findProfileDocs(uid) {
  const found = [];
  async function visit(ref) {
    const [snap, collections] = await Promise.all([ref.get(), ref.listCollections()]);
    if (snap.exists) found.push(ref);
    const children = await Promise.all(collections.map((collection) => collection.listDocuments()));
    for (const child of children.flat()) {
      // Deliberate sequential await (no-await-in-loop).
      await visit(child);
    }
  }
  await visit(db.doc(`users/${uid}`));
  return found;
}

// ════════════════════════════════════════════════════════════════
// SHARED: deleteAccountFor
// The deletion itself, for the deleteAccount callable (the caller's
// own account) and scripts/delete-account.js (an account named on
// its command line). Leaves the account's waiting lobbies,
// anonymizes its seats in played games, unlinks friends and friend
// requests, deletes the profile, then the sign-in account. Refused
// while the account is in or hosts a game in progress.
// ════════════════════════════════════════════════════════════════

/**
 * Deletes the account `uid`. Throws failed-precondition with the message the
 * clients show while the account is in or hosts a game in progress. Resolves
 * to what it did: the waiting lobbies it left (`lobbyIds`), the seats it
 * anonymized (`seatPaths`), how many friend lists it dropped the account
 * from (`friends`) and friend requests it deleted (`requests`), and whether
 * it deleted the sign-in account (`signInDeleted`, false when an earlier run
 * already had).
 */
async function deleteAccountFor(uid) {
  const games = await findGames(uid);

  // 1. Refuse during a live game, before anything is written: deleting
  //    mid-game would leave a ghost seat in a game others are still playing.
  //    A game the account only hosts counts too. startGame does not need the
  //    host to hold a seat, and endGame is host-only, so a live game whose
  //    host is deleted could never be ended.
  if (gameIdsInState(games, "in_progress").length > 0) {
    throw new HttpsError("failed-precondition", GAME_IN_PROGRESS_MESSAGE);
  }

  // 2. Leave waiting lobbies with leaveGame's own transaction.
  const lobbyIds = gameIdsInState(games, "waiting");
  for (const gameId of lobbyIds) {
    // Deliberate sequential await (no-await-in-loop).
    await leaveLobby(gameId, uid);
  }

  // 3. Anonymize the account's seats in every game it played or hosted.
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

  // 6. Delete the sign-in account last. If this throws, the account still
  //    exists, so its owner is still signed in and can retry; an account
  //    that is already gone means an earlier run got this far, which counts
  //    as done.
  let signInDeleted = true;
  try {
    await getAuth().deleteUser(uid);
  } catch (error) {
    if (error?.code !== "auth/user-not-found") throw error;
    signInDeleted = false;
  }

  return {
    lobbyIds,
    seatPaths: seatRefs.map((ref) => ref.path),
    friends: social.friends,
    requests: social.requests,
    signInDeleted,
  };
}

/**
 * What deleteAccountFor(uid) would do, found without writing anything: the
 * dry run of scripts/delete-account.js. `inProgressGameIds` lists the games
 * that would make it refuse, `lobbies` the waiting lobbies it would leave
 * (and whether the account hosts each), and `profilePaths` the documents
 * step 5 would delete. Leaving a lobby deletes the account's seat in it, so
 * `seatPaths` lists only the seats in the other games: the ones step 3
 * anonymizes.
 */
async function planAccountDeletion(uid) {
  const games = await findGames(uid);
  const lobbyIds = gameIdsInState(games, "waiting");
  const otherGameIds = [...games.keys()].filter((gameId) => !lobbyIds.includes(gameId));
  const [seatRefs, social, profileRefs] = await Promise.all([
    findSeats(otherGameIds, uid),
    findSocialData(uid),
    findProfileDocs(uid),
  ]);
  return {
    inProgressGameIds: gameIdsInState(games, "in_progress"),
    lobbies: lobbyIds.map((gameId) => ({ gameId, hosted: games.get(gameId).host_id === uid })),
    seatPaths: seatRefs.map((ref) => ref.path),
    friendPaths: social.friendRefs.map((ref) => ref.path),
    requestPaths: social.requestRefs.map((ref) => ref.path),
    profilePaths: profileRefs.map((ref) => ref.path),
  };
}

// Not deployed functions: index.js lists every deployed name explicitly.
exports.deleteAccountFor = deleteAccountFor;
exports.planAccountDeletion = planAccountDeletion;

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: deleteAccount
// Deletes the caller's account with deleteAccountFor. Refused
// while the caller is in or hosts a game in progress.
// ════════════════════════════════════════════════════════════════

exports.deleteAccount = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

  const deleted = await deleteAccountFor(uid);

  console.log(
    `deleteAccount: deleted ${uid} (left ${deleted.lobbyIds.length} lobbies, ` +
      `anonymized ${deleted.seatPaths.length} seats, unlinked ${deleted.friends} friends, ` +
      `deleted ${deleted.requests} friend requests)`
  );
  return { success: true };
});
