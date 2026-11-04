'use strict';

/**
 * INTEGRATION: notifyPlayers' dead-token cleanup (functions/src/notifications.js)
 *
 * FCM has no emulator, so inside the Functions emulator every send fails
 * before FCM answers and the cleanup never runs. This file runs the real
 * notifyPlayers in the test process instead, against the Firestore emulator,
 * with only Messaging replaced: a fake that reports tokens starting with
 * "dead-" as unregistered. The cleanup must clear a dead token wherever it is
 * stored, must never create users/{uid} or its private doc, and must never
 * delete a token the device registered after the one that died.
 */

const { describe, it, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const h = require('./helpers');

const sentTokens = [];
/** Runs inside a send, before FCM's answer comes back; reset per test. */
let whileSending = null;
const fakeMessaging = {
  async sendEachForMulticast({ tokens }) {
    sentTokens.push(...tokens);
    if (whileSending) await whileSending(tokens);
    const responses = tokens.map((token) =>
      token.startsWith('dead-')
        ? { success: false, error: { code: 'messaging/registration-token-not-registered' } }
        : { success: true }
    );
    return { failureCount: responses.filter((r) => !r.success).length, responses };
  },
};

// The cleanup's view of Firestore: the emulator, plus a record of every
// write it batches (a write that changes nothing leaves no other trace,
// not even a new updateTime) and a hook that runs right after it reads.
const batchedWrites = [];
let afterGetAll = null;
const cleanupDb = new Proxy(h.db, {
  get(target, prop) {
    if (prop === 'getAll') {
      return async (...args) => {
        const snaps = await target.getAll(...args);
        if (afterGetAll) await afterGetAll();
        return snaps;
      };
    }
    if (prop === 'batch') {
      return () => {
        const batch = target.batch();
        return new Proxy(batch, {
          get(b, method) {
            if (['set', 'update', 'delete', 'create'].includes(method)) {
              return (ref, ...rest) => {
                batchedWrites.push(ref.path);
                b[method](ref, ...rest);
                return b;
              };
            }
            const value = b[method];
            return typeof value === 'function' ? value.bind(b) : value;
          },
        });
      };
    }
    const value = target[prop];
    return typeof value === 'function' ? value.bind(target) : value;
  },
});

// notifications.js takes Firestore and Messaging from src/firebase.js, whose
// initializeApp() would clash with the Admin app helpers.js already started.
// Seed the module cache with the emulator-backed handles before loading it.
const firebaseModulePath = require.resolve('../../../src/firebase');
require.cache[firebaseModulePath] = {
  id: firebaseModulePath,
  filename: firebaseModulePath,
  loaded: true,
  exports: { db: cleanupDb, FieldValue: h.FieldValue, getMessaging: () => fakeMessaging },
};
const { notifyPlayers } = require('../../../src/notifications');

beforeEach(() => {
  whileSending = null;
  afterGetAll = null;
  batchedWrites.length = 0;
});

after(async () => {
  await h.shutdown();
});

function newUid(label) {
  return `${label}-${crypto.randomBytes(4).toString('hex')}`;
}

async function getDoc(path) {
  const snap = await h.db.doc(path).get();
  return snap.exists ? snap.data() : null;
}

/** Seeds a game seating `uids`; notifyPlayers only reads the seats' user_id. */
async function seedGame(uids) {
  const gameRef = h.db.collection('games').doc();
  await gameRef.set({
    code: crypto.randomBytes(3).toString('hex').toUpperCase(),
    host_id: uids[0],
    player_ids: uids,
    state: 'in_progress',
    game_mode: 'treachery',
    created_at: h.FieldValue.serverTimestamp(),
  });
  const batch = h.db.batch();
  uids.forEach((uid, i) => {
    batch.set(gameRef.collection('players').doc(`p${i}`), {
      user_id: uid,
      display_name: `Player ${i + 1}`,
      order_id: i,
    });
  });
  await batch.commit();
  return gameRef.id;
}

/** A profile plus a private doc holding `token`. */
async function seedUser(label, token) {
  const uid = newUid(label);
  await h.db.doc(`users/${uid}`).set({
    display_name: uid,
    created_at: h.FieldValue.serverTimestamp(),
  });
  await h.db.doc(`users/${uid}/private/data`).set({ fcm_token: token });
  return uid;
}

describe('notifyPlayers dead-token cleanup', () => {
  it("clears a profile-less account's dead token without creating its profile", async () => {
    const uid = newUid('no-profile');
    await h.db.doc(`users/${uid}/private/data`).set({ fcm_token: 'dead-private' });

    await notifyPlayers(await seedGame([uid]), null, 'Title', 'Body');

    assert.ok(sentTokens.includes('dead-private'), 'the token was sent, so the cleanup ran');
    assert.deepEqual(await getDoc(`users/${uid}/private/data`), {}, 'the dead token is gone');
    assert.equal(await getDoc(`users/${uid}`), null, 'no public profile may be created');
  });

  it('strips a dead legacy public token without creating a private doc', async () => {
    const uid = newUid('legacy');
    await h.db.doc(`users/${uid}`).set({
      display_name: 'Legacy Holder',
      created_at: h.FieldValue.serverTimestamp(),
      fcm_token: 'dead-public',
    });

    await notifyPlayers(await seedGame([uid]), null, 'Title', 'Body');

    assert.ok(sentTokens.includes('dead-public'));
    const profile = await getDoc(`users/${uid}`);
    assert.equal(profile.fcm_token, undefined, 'the legacy public copy is removed');
    assert.equal(profile.display_name, 'Legacy Holder', 'the rest of the profile is untouched');
    assert.equal(await getDoc(`users/${uid}/private/data`), null, 'no private doc may be created');
  });

  it('writes only the doc holding the dead token, and keeps live tokens', async () => {
    const deadUid = await seedUser('dead', 'dead-migrated');
    const liveUid = await seedUser('live', 'live-token');

    await notifyPlayers(await seedGame([deadUid, liveUid]), null, 'Title', 'Body');

    assert.ok(sentTokens.includes('dead-migrated') && sentTokens.includes('live-token'));
    assert.deepEqual(
      batchedWrites,
      [`users/${deadUid}/private/data`],
      'neither profile, nor the live private doc, is written at all'
    );
    assert.deepEqual(await getDoc(`users/${deadUid}/private/data`), {});
    assert.equal((await getDoc(`users/${liveUid}/private/data`)).fcm_token, 'live-token');
  });

  it('keeps a token the device registered while the send was in flight', async () => {
    const uid = await seedUser('replaced', 'dead-replaced');
    whileSending = async () => {
      // registerFcmToken, called by the device between the send and FCM's answer.
      await h.db.doc(`users/${uid}/private/data`).set({ fcm_token: 'fresh-token' }, { merge: true });
    };

    await notifyPlayers(await seedGame([uid]), null, 'Title', 'Body');

    assert.ok(sentTokens.includes('dead-replaced'));
    assert.equal((await getDoc(`users/${uid}/private/data`)).fcm_token, 'fresh-token');
    assert.deepEqual(batchedWrites, [], 'nothing held the dead token any more');
  });

  it('keeps a token registered between the cleanup reading it and writing', async () => {
    const uid = await seedUser('raced', 'dead-raced');
    // Armed during the send, so it fires after the cleanup's read, not after
    // the token lookup that comes before the send.
    whileSending = async () => {
      afterGetAll = async () => {
        afterGetAll = null;
        await h.db.doc(`users/${uid}/private/data`).set({ fcm_token: 'fresh-raced' }, { merge: true });
      };
    };
    const errors = [];
    const consoleError = console.error;
    console.error = (...args) => errors.push(args);
    try {
      await notifyPlayers(await seedGame([uid]), null, 'Title', 'Body');
    } finally {
      console.error = consoleError;
    }

    assert.deepEqual(batchedWrites, [`users/${uid}/private/data`], 'the cleanup did try to clear it');
    assert.equal(
      (await getDoc(`users/${uid}/private/data`)).fcm_token,
      'fresh-raced',
      'the update was refused because the doc changed after it was read'
    );
    assert.deepEqual(errors, [], 'a refused update is expected, not an error');
  });
});
