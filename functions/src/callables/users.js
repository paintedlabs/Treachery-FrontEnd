// Per-user callables: FCM token registration and friend management.
// None of these touch games/*.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { callableOptions } = require("../config");
const { db, FieldValue } = require("../firebase");
const { privateUserRef } = require("../notifications");

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

  // Store on owner-only private doc; strip any leftover public field.
  await privateUserRef(uid).set({ fcm_token: token }, { merge: true });
  await db.doc(`users/${uid}`).set({ fcm_token: FieldValue.delete() }, { merge: true });

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
