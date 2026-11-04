'use strict';

/**
 * Preloaded into scripts/delete-account.js (`node --require`) by
 * delete-account-script.test.js, to make one thing happen at one moment of a
 * deletion, inside the script's own process. DELETE_ACCOUNT_FAULT names it,
 * and DELETE_ACCOUNT_FAULT_UID is the account the script deletes:
 *
 *   start-lobbies-before-deleting
 *       Every waiting lobby the account is in starts after the script's
 *       checks have passed, just before deleteAccountFor runs.
 *   start-lobbies-before-second-leave
 *       Once it has left one lobby, every waiting lobby it is still in
 *       starts before it leaves the next.
 *   fail-friend-request-batch
 *       The batch that deletes its friend requests (step 4) fails.
 *   fail-delete-under-profile
 *       Step 5 can't delete the documents under users/{uid}, such as
 *       private/data, and deletes users/{uid} itself anyway, as Firestore's
 *       recursiveDelete does when one of its deletes fails for good.
 *   fail-sign-in-delete
 *       Deleting its sign-in account (step 6) fails.
 *
 * Nothing here loads src/: the script must make the default app before
 * src/firebase.js is loaded, or that module makes one from the environment.
 */

const Module = require('node:module');
const path = require('node:path');
const { getFirestore, Firestore, WriteBatch, BulkWriter } = require('firebase-admin/firestore');
const { BaseAuth } = require('firebase-admin/auth');

const FAULT = process.env.DELETE_ACCOUNT_FAULT;
const UID = process.env.DELETE_ACCOUNT_FAULT_UID;
const ACCOUNT_MODULE = path.resolve(__dirname, '../../../src/callables/account.js');

// The gRPC status for a backend that can't be reached: one no step treats as
// done or retries.
const UNAVAILABLE = 14;

/** Starts every waiting lobby that lists the account, as startGame would. */
async function startLobbies(db) {
  const snap = await db.collection('games').where('player_ids', 'array-contains', UID).get();
  const lobbies = snap.docs.filter((doc) => doc.get('state') === 'waiting');
  await Promise.all(lobbies.map((doc) => doc.ref.update({ state: 'in_progress' })));
}

function injected(what, code) {
  const error = new Error(`delete-account-faults.js: ${what} failed`);
  error.code = code;
  return error;
}

/** Calls `wrap(exports)` once, when the script loads src/callables/account.js. */
function onAccountModuleLoaded(wrap) {
  const load = Module._load;
  let wrapped = false;
  Module._load = function loadAndWrap(request, parent, isMain) {
    const exported = load.call(this, request, parent, isMain);
    if (!wrapped && Module._resolveFilename(request, parent, isMain) === ACCOUNT_MODULE) {
      wrapped = true;
      wrap(exported);
    }
    return exported;
  };
}

if (!UID) throw new Error('delete-account-faults.js: set DELETE_ACCOUNT_FAULT_UID');

switch (FAULT) {
  case 'start-lobbies-before-deleting':
    onAccountModuleLoaded((account) => {
      const { deleteAccountFor } = account;
      account.deleteAccountFor = async (uid) => {
        await startLobbies(getFirestore());
        return deleteAccountFor(uid);
      };
    });
    break;

  case 'start-lobbies-before-second-leave': {
    // Each lobby is left in a transaction of its own, and nothing else in the
    // script runs one.
    const runTransaction = Firestore.prototype.runTransaction;
    let transactions = 0;
    Firestore.prototype.runTransaction = async function startThenRun(...args) {
      transactions += 1;
      if (transactions === 2) await startLobbies(this);
      return runTransaction.apply(this, args);
    };
    break;
  }

  case 'fail-friend-request-batch': {
    const deletesFriendRequest = new WeakSet();
    const deleteDoc = WriteBatch.prototype.delete;
    WriteBatch.prototype.delete = function markThenDelete(ref, ...rest) {
      if (ref.path.startsWith('friend_requests/')) deletesFriendRequest.add(this);
      return deleteDoc.call(this, ref, ...rest);
    };
    const commit = WriteBatch.prototype.commit;
    WriteBatch.prototype.commit = function failOrCommit(...args) {
      if (deletesFriendRequest.has(this)) {
        return Promise.reject(injected('the batch that deletes friend requests', UNAVAILABLE));
      }
      return commit.apply(this, args);
    };
    break;
  }

  case 'fail-delete-under-profile': {
    // recursiveDelete deletes each document under users/{uid} through a
    // BulkWriter, then queues the delete of users/{uid} itself whether or not
    // those succeeded.
    const deleteDoc = BulkWriter.prototype.delete;
    BulkWriter.prototype.delete = function failUnderProfile(ref, ...rest) {
      if (ref.path.startsWith(`users/${UID}/`)) {
        return Promise.reject(injected(`deleting ${ref.path}`, UNAVAILABLE));
      }
      return deleteDoc.call(this, ref, ...rest);
    };
    break;
  }

  case 'fail-sign-in-delete':
    BaseAuth.prototype.deleteUser = () =>
      Promise.reject(injected('deleting the sign-in account', 'auth/internal-error'));
    break;

  default:
    throw new Error(`delete-account-faults.js: unknown DELETE_ACCOUNT_FAULT ${JSON.stringify(FAULT)}`);
}
