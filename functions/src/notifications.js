// FCM token lookup and push-notification fan-out.

const { db, FieldValue, getMessaging } = require("./firebase");

/** Owner-only private profile path (email / phone / FCM). */
function privateUserRef(uid) {
  return db.doc(`users/${uid}/private/data`);
}

/**
 * Resolves FCM tokens for several users at once, index-aligned with `uids`
 * (null where the user has no token). Batched: one getAll for the private
 * docs, plus a second only for the users whose token has not migrated yet.
 * `uids` must be free of duplicates — getAll resolves responses by path.
 */
async function getUserFcmTokens(uids) {
  if (uids.length === 0) return [];

  const privateSnaps = await db.getAll(...uids.map((uid) => privateUserRef(uid)));
  const tokens = privateSnaps.map((snap) =>
    snap.exists ? snap.data()?.fcm_token || null : null
  );

  // Legacy: token still living on the public user doc
  const legacyIndexes = tokens
    .map((token, idx) => (token ? -1 : idx))
    .filter((idx) => idx >= 0);
  if (legacyIndexes.length > 0) {
    const publicSnaps = await db.getAll(
      ...legacyIndexes.map((idx) => db.doc(`users/${uids[idx]}`))
    );
    publicSnaps.forEach((snap, n) => {
      tokens[legacyIndexes[n]] = snap.exists ? snap.data()?.fcm_token || null : null;
    });
  }

  return tokens;
}

// ── FCM Notification Helper ──

/**
 * Sends a push notification to all players in a game (except the excluded user).
 * Silently skips users without FCM tokens or invalid tokens.
 */
async function notifyPlayers(gameId, excludeUserId, title, body) {
  try {
    // Get player user IDs from the game. Deduped and blank-filtered because
    // the batched read below needs distinct, well-formed document paths.
    const playersSnap = await db.collection(`games/${gameId}/players`).get();
    const userIds = [
      ...new Set(
        playersSnap.docs
          .map((d) => d.data().user_id)
          .filter((uid) => uid && uid !== excludeUserId)
      ),
    ];

    if (userIds.length === 0) return;

    // Fetch FCM tokens from private (or legacy public) user data.
    // tokenEntries stays index-aligned with the tokens sent below, which the
    // invalid-token cleanup relies on to map a failure back to its user.
    const fcmTokens = await getUserFcmTokens(userIds);
    const tokenEntries = []; // { uid, token }
    userIds.forEach((uid, idx) => {
      if (fcmTokens[idx]) tokenEntries.push({ uid, token: fcmTokens[idx] });
    });

    if (tokenEntries.length === 0) return;

    const tokens = tokenEntries.map((e) => e.token);
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

    // Clean up invalid tokens on the user that produced them
    if (response.failureCount > 0) {
      const batch = db.batch();
      let dirty = false;
      response.responses.forEach((resp, idx) => {
        if (
          resp.error &&
          (resp.error.code === "messaging/invalid-registration-token" ||
            resp.error.code === "messaging/registration-token-not-registered")
        ) {
          const { uid } = tokenEntries[idx];
          batch.set(
            privateUserRef(uid),
            { fcm_token: FieldValue.delete() },
            { merge: true }
          );
          batch.set(
            db.doc(`users/${uid}`),
            { fcm_token: FieldValue.delete() },
            { merge: true }
          );
          dirty = true;
        }
      });
      if (dirty) await batch.commit();
    }
  } catch (error) {
    // Non-fatal: notification failure shouldn't break game logic
    console.error("FCM notification error:", error);
  }
}

module.exports = {
  privateUserRef,
  notifyPlayers,
};
