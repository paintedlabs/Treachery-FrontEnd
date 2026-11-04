'use strict';

/**
 * INTEGRATION: exports.registerFcmToken (functions/index.js)
 *
 * Stores a device's FCM token on the caller's owner-only private doc. A
 * sign-in token stays valid for up to an hour after deleteAccount removes
 * its account, so the callable must not recreate a deleted user's data,
 * while a live account registers exactly as before. It must never create
 * the public profile either: an empty one is unreadable to every client.
 * Users come from h.createUser() because one of them is deleted.
 */

const { describe, it, after } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

after(async () => {
  await h.shutdown();
});

async function getDoc(path) {
  const snap = await h.db.doc(path).get();
  return snap.exists ? snap.data() : null;
}

describe('registerFcmToken', () => {
  it("stores the token on the caller's private doc and strips the public copy", async () => {
    const user = await h.createUser('Token Owner');
    await h.db.doc(`users/${user.uid}`).update({ fcm_token: 'legacy-token' });

    assert.deepEqual(
      await user.call('registerFcmToken', { token: 'new-token' }),
      { success: true }
    );

    assert.equal((await getDoc(`users/${user.uid}/private/data`)).fcm_token, 'new-token');
    const profile = await getDoc(`users/${user.uid}`);
    assert.equal(profile.fcm_token, undefined, 'the legacy public copy is removed');
    assert.equal(profile.display_name, 'Token Owner', 'the rest of the profile is untouched');
  });

  it('registers for an account with no profile without creating one', async () => {
    // Sign-up can race the client's own profile write, and some accounts
    // never got a profile at all.
    const user = await h.createUser('Brand New');
    await h.db.doc(`users/${user.uid}`).delete();

    assert.deepEqual(
      await user.call('registerFcmToken', { token: 'first-token' }),
      { success: true }
    );

    assert.equal((await getDoc(`users/${user.uid}/private/data`)).fcm_token, 'first-token');
    assert.equal(
      await getDoc(`users/${user.uid}`),
      null,
      'no public profile may be created; the client creates it'
    );
  });

  // Only the profile's data can be compared here: the callable runs in the
  // Functions emulator, out of reach of a write recorder, and a write that
  // changes nothing doesn't even move updateTime. The cases that matter,
  // creating a missing profile and stripping a real leftover, are above.
  it('leaves the data of a profile with no public token as it was', async () => {
    const user = await h.createUser('Already Migrated');
    const before = await getDoc(`users/${user.uid}`);

    assert.deepEqual(
      await user.call('registerFcmToken', { token: 'fresh-token' }),
      { success: true }
    );

    assert.deepEqual(await getDoc(`users/${user.uid}`), before, 'no field of the profile changes');
    assert.equal((await getDoc(`users/${user.uid}/private/data`)).fcm_token, 'fresh-token');
  });

  it("refuses a deleted account's still-valid token and recreates nothing", async () => {
    const user = await h.createUser('Gone For Good');
    assert.deepEqual(await user.call('deleteAccount', {}), { success: true });

    await h.expectHttpsError(
      user.call('registerFcmToken', { token: 'late-token' }),
      'unauthenticated'
    );

    assert.equal(await getDoc(`users/${user.uid}`), null, 'the profile must stay deleted');
    assert.equal(
      await getDoc(`users/${user.uid}/private/data`),
      null,
      'no device token may be stored for a deleted account'
    );
  });
});
