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
      const deadTokens = [];
      response.responses.forEach((resp, idx) => {
        if (
          resp.error &&
          (resp.error.code === "messaging/invalid-registration-token" ||
            resp.error.code === "messaging/registration-token-not-registered")
        ) {
          deadTokens.push(tokenEntries[idx]);
        }
      });
      await clearFcmTokens(deadTokens);
    }
  } catch (error) {
    // Non-fatal: notification failure shouldn't break game logic
    console.error("FCM notification error:", error);
  }
}

// The gRPC status the Firestore Admin SDK reports when a write's
// precondition (here, "unchanged since read") no longer holds.
const FIRESTORE_FAILED_PRECONDITION = 9;

/**
 * Deletes each token FCM rejected from where it is stored, writing only
 * docs that exist and still hold it. A set with merge would create a
 * missing doc, giving a profile-less (or deleted) account an empty public
 * profile.
 *
 * - users/{uid}/private/data loses `fcm_token` only while it still holds the
 *   rejected token: the device may have registered a new one since the
 *   send, and that one must stay.
 * - users/{uid} loses any `fcm_token` it holds. A public copy is a leftover
 *   from before the PII split, never a live registration.
 *
 * Every update also requires the doc to be unchanged since it was read here,
 * so a token registered in between is never deleted. If one was, the batch
 * is skipped; a later failed send cleans up whatever is still dead.
 *
 * @param {{uid: string, token: string}[]} deadTokens At most one per uid.
 */
async function clearFcmTokens(deadTokens) {
  if (deadTokens.length === 0) return;

  // Path -> the token that doc must still hold to be cleared (null: any).
  const clearIfHolding = new Map();
  deadTokens.forEach(({ uid, token }) => {
    clearIfHolding.set(privateUserRef(uid).path, token);
    clearIfHolding.set(`users/${uid}`, null);
  });
  const snaps = await db.getAll(...[...clearIfHolding.keys()].map((path) => db.doc(path)));
  const holders = snaps.filter((snap) => {
    const stored = snap.exists ? snap.get("fcm_token") : undefined;
    if (stored === undefined) return false;
    const deadToken = clearIfHolding.get(snap.ref.path);
    return deadToken === null || stored === deadToken;
  });
  if (holders.length === 0) return;

  const batch = db.batch();
  holders.forEach((snap) =>
    batch.update(snap.ref, { fcm_token: FieldValue.delete() }, { lastUpdateTime: snap.updateTime })
  );
  try {
    await batch.commit();
  } catch (error) {
    if (error?.code !== FIRESTORE_FAILED_PRECONDITION) throw error;
    console.log("FCM token cleanup skipped: a user doc changed while it ran");
  }
}

module.exports = {
  privateUserRef,
  notifyPlayers,
};
