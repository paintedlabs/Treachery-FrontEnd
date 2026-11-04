// Per-user callables: FCM token registration and friend management.
// None of these touch games/*.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { callableOptions } = require("../config");
const { db, FieldValue, getAuth } = require("../firebase");
const { privateUserRef } = require("../notifications");

/**
 * True only when Auth confirms `uid` has no account. Any other lookup
 * failure is not proof, so the caller carries on as if the account exists.
 */
async function isDeletedAccount(uid) {
  try {
    await getAuth().getUser(uid);
    return false;
  } catch (error) {
    return error?.code === "auth/user-not-found";
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

  // An ID token stays valid for up to an hour after deleteAccount removes
  // its account. The writes below would then recreate the deleted profile
  // and store this device's token under it, and nothing would ever clean
  // that up. Only a missing profile costs the Auth lookup, and a new
  // account whose profile is not written yet still registers.
  const profileSnap = await db.doc(`users/${uid}`).get();
  if (!profileSnap.exists && (await isDeletedAccount(uid))) {
    throw new HttpsError("unauthenticated", "This account has been deleted.");
  }

  // Store on owner-only private doc.
  await privateUserRef(uid).set({ fcm_token: token }, { merge: true });

  // Strip a leftover public copy, but only from a profile that exists and
  // still has one. An update never creates the doc: a set with merge here
  // used to give a profile-less account an empty public profile, which no
  // client could read or repair.
  if (profileSnap.exists && profileSnap.get("fcm_token") !== undefined) {
    await profileSnap.ref.update({ fcm_token: FieldValue.delete() });
  }

  return { success: true };
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
