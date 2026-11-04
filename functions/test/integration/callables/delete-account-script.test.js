'use strict';

/**
 * INTEGRATION: functions/scripts/delete-account.js
 *
 * The script a developer runs against production to delete an account whose
 * owner asked for it by email, because the web and Android apps can't delete
 * accounts yet. It runs deleteAccountFor, the deleteAccount callable's own
 * steps, so these tests run it on the command line, as the developer does,
 * against the suite's emulators, and hold its result to the callable's: the
 * same seed, deleted once by each, must end in the same state. Every account
 * here is new (h.createUser() or adminAuth.createUser()), never the shared
 * pool: a deleted pooled account would break every later test that reuses
 * it. Runs that need a lobby to start, or a write to fail, part-way through
 * a deletion preload delete-account-faults.js into the script.
 */

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { getAuth } = require('firebase-admin/auth');
const { Timestamp } = require('firebase-admin/firestore');
const h = require('./helpers');

const SCRIPT = path.resolve(__dirname, '../../../scripts/delete-account.js');
const FAULTS = path.resolve(__dirname, 'delete-account-faults.js');
const PROJECT_ID = process.env.GCLOUD_PROJECT || 'demo-test';
// helpers.js points both at the suite's emulators when they aren't set.
const FIRESTORE_HOST = process.env.FIRESTORE_EMULATOR_HOST;
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST;
// The Admin app helpers.js started, on the Auth emulator.
const adminAuth = getAuth();

after(async () => {
  await h.shutdown();
});

// The code the requester sets as their display name, as the policy describes.
const CODE = 'Lantern-4821';
const DELETED_NAME = 'Deleted player';

/**
 * Runs the script on the command line with the suite's environment plus
 * `env` (an undefined value removes a variable), with Firestore and Auth on
 * the suite's emulators unless `env` says otherwise, each of `preloads`
 * loaded into it first, and `input` on its stdin (none by default).
 *
 * Without Application Default Credentials, the Firestore client looks for a
 * GCE metadata server and prints a MetadataLookupWarning to stderr when there
 * is none. The emulators need no credentials, so the lookup is switched off
 * and stderr holds only what the script prints.
 */
function runScript(args, env = {}, preloads = [], input = undefined) {
  return spawnSync(process.execPath, [...preloads.flatMap((file) => ['--require', file]), SCRIPT, ...args], {
    env: {
      ...process.env,
      METADATA_SERVER_DETECTION: 'none',
      FIRESTORE_EMULATOR_HOST: FIRESTORE_HOST,
      FIREBASE_AUTH_EMULATOR_HOST: AUTH_HOST,
      ...env,
    },
    input,
    encoding: 'utf8',
    timeout: 120_000,
  });
}

/** runScript, with `input` on the script's stdin, as `--expect-name -` reads it. */
function runScriptWithInput(input, args) {
  return runScript(args, {}, [], input);
}

/** runScript, with `fault` (see delete-account-faults.js) happening to `account`. */
function runScriptWithFault(fault, account, args) {
  return runScript(args, { DELETE_ACCOUNT_FAULT: fault, DELETE_ACCOUNT_FAULT_UID: account.uid }, [FAULTS]);
}

/** A line of the script's report: a label and its value, aligned. */
function row(label, value) {
  return `  ${label.padEnd(32)}${value}`;
}

/** The lines the script prints first: where it reads and writes. */
function header(mode) {
  return [
    `project:  ${PROJECT_ID} (from --project)`,
    `target:   emulator ${FIRESTORE_HOST}`,
    `mode:     ${mode}`,
    `auth:     emulator ${AUTH_HOST}`,
    '',
  ];
}

/**
 * How an --apply ends: when to check on it. The hour runs from when the
 * sign-in account was deleted, by this run unless `until` says otherwise.
 */
function checkLater(uid, until = 'an hour from now') {
  return [
    '',
    `A web or Android app still signed in to it can recreate its profile until ${until}.`,
    `Then run this with --uid ${uid} and without --apply: it should find no such account.`,
  ];
}

/** checkLater's `until` for an --apply that found the sign-in account already deleted. */
const AFTER_EARLIER_SIGN_IN_DELETE = 'an hour after its sign-in account was deleted';

/** How a run by uid ends when nothing of the account is left. */
function noSuchUid(uid) {
  return (
    `refused: no such account: no sign-in account or profile has uid ${uid}, ` +
    `and nothing is left under users/${uid}.\n`
  );
}

/**
 * The refusal for an account that has a sign-in account but no profile,
 * naming the documents still under its users/{uid}.
 */
function noProfile(uid, leftovers = []) {
  const left = leftovers.length > 0 ? ` Documents are still left under it: ${leftovers.join(', ')}.` : '';
  return (
    `refused: users/${uid} doesn't exist, so there's no display name to check --expect-name against.${left} ` +
    `If an earlier --apply for this account stopped part-way, delete the sign-in account ${uid} in the ` +
    `Firebase console (Authentication), then run this again with --uid ${uid}: with no sign-in account or ` +
    `profile left, it deletes anything still under users/${uid} without checking the name. An hour after ` +
    `you delete the sign-in account, run this with --uid ${uid} and without --apply: it should find no such ` +
    'account. If no --apply has run for it, the account has no profile yet: its owner makes one by signing ' +
    'in to Treachery on the web or Android, and can then set the code.\n'
  );
}

/** What a run says when only documents under a deleted account's users/{uid} are left. */
const LEFTOVERS_ONLY =
  "No sign-in account or profile is left, only what an earlier deletion left behind, so --expect-name isn't checked.";

/** The refusal when a lobby the account is in starts after the checks. */
function startedAfterCheck(uid) {
  return (
    `refused: ${uid} is now in a game in progress: a lobby it was in started after the check. ` +
    'The deletion stopped before changing anything but the lobbies it had already left. ' +
    'Run this again once that game ends.\n'
  );
}

/** How a run that failed once the deletion had begun ends. */
function stoppedPartWay(uid) {
  return (
    'failed: the deletion stopped part-way. Every step is safe to repeat, so run the same command ' +
    `again to finish. If that is refused because users/${uid} doesn't exist, this run got as far as ` +
    `deleting the profile: delete the sign-in account ${uid} in the Firebase console (Authentication), ` +
    `then run this again with --uid ${uid} to delete anything still under users/${uid}. An hour after you ` +
    `delete the sign-in account, not an hour after this run, run this with --uid ${uid} and without ` +
    '--apply: it should find no such account.\n'
  );
}

// Each run gets its own block of phone numbers, so no two accounts share one.
const PHONE_BLOCK = crypto.randomInt(100, 1000);
let contacts = 0;

/** An email address and phone number that no other account has. */
function uniqueContact(label) {
  contacts += 1;
  return {
    email: `${label}.${crypto.randomBytes(3).toString('hex')}${contacts}@example.com`,
    phone: `+1650${PHONE_BLOCK}${String(contacts).padStart(4, '0')}`,
  };
}

/** "lantern@example.com" → "l***@example.com", as the script masks it. */
function maskedEmail(email) {
  return `${email[0]}***${email.slice(email.indexOf('@'))}`;
}

/** "+16501230001" → "+*******0001", as the script masks it. */
function maskedPhone(phone) {
  return `+${'*'.repeat(phone.length - 5)}${phone.slice(-4)}`;
}

/**
 * An account that signs in with email and password and with a phone number,
 * holding the profile the clients write. Not signed in anywhere: only the
 * script acts on it.
 */
async function createSignInAccount(displayName, contact) {
  const record = await adminAuth.createUser({
    email: contact.email,
    phoneNumber: contact.phone,
    password: 'emulator-only-password',
  });
  await h.db.doc(`users/${record.uid}`).set({
    display_name: displayName,
    elo: 1500,
    created_at: h.FieldValue.serverTimestamp(),
  });
  return { uid: record.uid, displayName };
}

/** Makes `a` and `b` mutual friends, as acceptFriendRequest does. */
async function befriend(a, b) {
  await h.db.doc(`users/${a.uid}`).update({ friend_ids: h.FieldValue.arrayUnion(b.uid) });
  await h.db.doc(`users/${b.uid}`).update({ friend_ids: h.FieldValue.arrayUnion(a.uid) });
}

/** Seeds a friend_requests doc shaped the way the clients write one. */
async function seedFriendRequest(from, to, status = 'pending') {
  const ref = h.db.collection('friend_requests').doc();
  await ref.set({
    from_user_id: from.uid,
    from_display_name: from.displayName,
    to_user_id: to.uid,
    status,
    created_at: h.FieldValue.serverTimestamp(),
  });
  return ref;
}

/**
 * Seeds the people and data around `account` that deleting it has to deal
 * with: private data, two friends, a pending friend request in each
 * direction, a seat in a finished game, and a waiting lobby it hosts with
 * one other player. The other people have the same names in every seed, so
 * two seeds differ only in their ids.
 */
async function seedAccount(account, contact) {
  const people = {};
  for (const role of ['friendA', 'friendB', 'requestTarget', 'requestSender', 'opponent', 'lobbyMate']) {
    // Deliberate sequential await (no-await-in-loop).
    people[role] = await h.createUser(`Seeded ${role}`);
  }
  await h.db.doc(`users/${account.uid}/private/data`).set({
    email: contact.email,
    phone_number: contact.phone,
    fcm_token: 'fcm-token',
  });
  await befriend(account, people.friendA);
  await befriend(account, people.friendB);
  const sent = await seedFriendRequest(account, people.requestTarget);
  const received = await seedFriendRequest(people.requestSender, account);
  const finished = await h.seedGame({
    users: [account, people.opponent],
    state: 'finished',
    gameFields: { winning_team: 'assassin' },
    playerOverrides: {
      0: {
        role: 'leader',
        identity_card_id: 'leader_01',
        life_total: 0,
        is_eliminated: true,
        is_unveiled: true,
        commander_name: 'Atraxa',
      },
      1: {
        role: 'assassin',
        identity_card_id: 'assassin_01',
        life_total: 17,
        commander_name: 'Edgar Markov',
      },
    },
  });
  const lobby = await h.seedGame({ users: [account, people.lobbyMate] });
  return { account, people, sent, received, finished, lobby };
}

/** Every document of `seed` that deleting its account could change. */
function seededPaths({ account, people, sent, received, finished, lobby }) {
  return [
    `users/${account.uid}`,
    `users/${account.uid}/private/data`,
    ...Object.values(people).map((person) => `users/${person.uid}`),
    sent.path,
    received.path,
    `games/${finished.gameId}`,
    ...finished.players.map((seat) => `games/${finished.gameId}/players/${seat.id}`),
    `games/${lobby.gameId}`,
    ...lobby.players.map((seat) => `games/${lobby.gameId}/players/${seat.id}`),
  ];
}

/** Each path's data and updateTime, or null for a document that doesn't exist. */
async function readDocs(paths) {
  const snaps = await h.db.getAll(...paths.map((docPath) => h.db.doc(docPath)));
  return new Map(
    snaps.map((snap) => [snap.ref.path, snap.exists ? { data: snap.data(), updateTime: snap.updateTime } : null])
  );
}

/**
 * Asserts that no document in `before` changed by `now`. onPlayerJoined
 * stamps a game's last_activity_at a moment after each seat the seed
 * creates, so a game can still change through that field alone; the script
 * writes a game only by leaving it, which changes its player_ids or host_id.
 * Every other document must not be written at all.
 */
function assertUnchanged(before, now) {
  for (const [docPath, was] of before) {
    const is = now.get(docPath);
    if (was === null) {
      assert.equal(is, null, `${docPath} must not be created`);
      continue;
    }
    assert.ok(is, `${docPath} must still exist`);
    if (/^games\/[^/]+$/.test(docPath)) {
      const { last_activity_at: _wasStamped, ...wasData } = was.data;
      const { last_activity_at: _isStamped, ...isData } = is.data;
      assert.deepEqual(isData, wasData, `${docPath} must keep its data`);
      continue;
    }
    assert.deepEqual(is.data, was.data, `${docPath} must keep its data`);
    assert.ok(is.updateTime.isEqual(was.updateTime), `${docPath} must not be written`);
  }
}

/** The sign-in account as Admin Auth reports it, or null when there is none. */
async function signInAccount(uid) {
  const record = await h.getAuthUser(uid);
  return record ? record.toJSON() : null;
}

/**
 * The state of everything around `seed`'s account, with each seeded uid
 * replaced by its role, each timestamp by "timestamp" and each join code by
 * "code": what two seeds differ in when they are otherwise the same.
 */
async function endState(seed) {
  const { account, people, sent, received, finished, lobby } = seed;
  const roles = new Map([
    [account.uid, 'account'],
    ...Object.entries(people).map(([role, person]) => [person.uid, role]),
  ]);
  const normalize = (value, key) => {
    if (key === 'code') return 'code';
    if (value instanceof Timestamp) return 'timestamp';
    if (typeof value === 'string') return roles.get(value) ?? value;
    if (Array.isArray(value)) return value.map((item) => normalize(item));
    if (value && typeof value === 'object') {
      return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, normalize(v, k)]));
    }
    return value;
  };
  const read = async (docPath) => {
    const snap = await h.db.doc(docPath).get();
    return snap.exists ? normalize(snap.data()) : null;
  };
  const seats = async (gameId) => (await h.getPlayers(gameId)).map((seat) => normalize(seat));
  const others = {};
  for (const [role, person] of Object.entries(people)) {
    // Deliberate sequential await (no-await-in-loop).
    others[role] = await read(`users/${person.uid}`);
  }
  return {
    profile: await read(`users/${account.uid}`),
    privateData: await read(`users/${account.uid}/private/data`),
    profileCollections: (await h.db.doc(`users/${account.uid}`).listCollections()).map((c) => c.id),
    signIn: (await h.getAuthUser(account.uid)) !== null,
    people: others,
    sentRequest: await read(sent.path),
    receivedRequest: await read(received.path),
    finishedGame: await read(`games/${finished.gameId}`),
    finishedSeats: await seats(finished.gameId),
    lobby: await read(`games/${lobby.gameId}`),
    lobbySeats: await seats(lobby.gameId),
  };
}

describe('delete-account script — dry run, --apply, and a second run', () => {
  const contact = uniqueContact('lantern');
  let seed; // deleted by the script
  let twin; // the same seed, deleted by the deleteAccount callable
  let afterApply;

  before(async () => {
    seed = await seedAccount(await createSignInAccount(CODE, contact), contact);
    twin = await seedAccount(await h.createUser(CODE), contact);
  });

  it('a dry run shows the account and what deleting it would do, and changes nothing', async () => {
    const { account, people, sent, received, finished, lobby } = seed;
    const paths = seededPaths(seed);
    const before = await readDocs(paths);
    const authBefore = await signInAccount(account.uid);

    const result = runScript(['--uid', account.uid, '--expect-name', CODE, '--project', PROJECT_ID]);

    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stderr, '');
    const friendPaths = [people.friendA, people.friendB].map((p) => `users/${p.uid}`).sort();
    assert.deepEqual(result.stdout.split('\n'), [
      ...header('DRY RUN (no writes)'),
      'account:',
      row('uid:', account.uid),
      row('display name:', JSON.stringify(CODE)),
      row('sign-in providers:', 'password, phone'),
      row('email:', maskedEmail(contact.email)),
      row('phone:', maskedPhone(contact.phone)),
      '',
      'deleting it would:',
      row('leave waiting lobbies:', `1  games/${lobby.gameId} (hosts it)`),
      row('anonymize its seats in games:', `1  games/${finished.gameId}`),
      row("take it off friends' lists:", `2  ${friendPaths.join(', ')}`),
      row('delete friend requests:', `2  ${sent.path}, ${received.path}`),
      row('delete profile documents:', `2  users/${account.uid}, users/${account.uid}/private/data`),
      row('delete the sign-in account:', `1  ${account.uid}`),
      '',
      'DRY RUN — nothing was written. Re-run with --apply --project <id> to delete this account.',
      '',
    ]);
    // Masked: the address, its local part and the number never appear whole.
    for (const secret of [contact.email, contact.email.split('@')[0], contact.phone]) {
      assert.ok(!result.stdout.includes(secret), `the output must not contain ${secret}`);
    }

    assertUnchanged(before, await readDocs(paths));
    assert.deepEqual(await signInAccount(account.uid), authBefore, 'the sign-in account must be untouched');
  });

  it('--apply leaves the same state as the deleteAccount callable does for the same seed', async () => {
    const { account, lobby, finished } = seed;

    assert.deepEqual(await twin.account.call('deleteAccount', {}), { success: true });
    const result = runScript(['--uid', account.uid, '--expect-name', CODE, '--apply', '--project', PROJECT_ID]);

    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stderr, '');
    const lines = result.stdout.split('\n');
    assert.deepEqual(lines.slice(0, 5), header('APPLY (writes)'), 'it names the project before writing');
    assert.deepEqual(lines.slice(lines.indexOf(`deleting ${account.uid} from ${PROJECT_ID} …`)), [
      `deleting ${account.uid} from ${PROJECT_ID} …`,
      `deleted ${account.uid}:`,
      row('left waiting lobbies:', `1  games/${lobby.gameId}`),
      row('anonymized its seats in games:', `1  games/${finished.gameId}`),
      row("took it off friends' lists:", '2'),
      row('deleted friend requests:', '2'),
      row('deleted the profile:', `users/${account.uid} and everything under it`),
      row('deleted the sign-in account:', 'yes'),
      ...checkLater(account.uid),
      '',
    ]);

    const state = await endState(seed);
    assert.deepEqual(state, await endState(twin), 'the script and the callable must leave the same state');

    // That state is the deletion delete-account.test.js describes.
    assert.equal(state.profile, null, 'the profile must be deleted');
    assert.equal(state.privateData, null, 'the private doc must be deleted');
    assert.deepEqual(state.profileCollections, [], 'no subcollection may be left behind');
    assert.equal(state.signIn, false, 'the sign-in account must be deleted');
    assert.deepEqual(state.people.friendA.friend_ids, []);
    assert.deepEqual(state.people.friendB.friend_ids, []);
    assert.equal(state.sentRequest, null, 'the request it sent must be deleted');
    assert.equal(state.receivedRequest, null, 'the request it received must be deleted');
    const [seat, theirs] = state.finishedSeats;
    assert.equal(seat.display_name, DELETED_NAME);
    assert.equal(seat.commander_name, undefined, 'commander_name must be removed');
    assert.equal(seat.user_id, 'account', 'user_id stays so history and stats stay coherent');
    assert.equal(seat.role, 'leader');
    assert.equal(seat.life_total, 0);
    assert.equal(theirs.display_name, 'Seeded opponent', 'other seats are untouched');
    assert.equal(theirs.commander_name, 'Edgar Markov');
    assert.equal(state.finishedGame.winning_team, 'assassin');
    assert.deepEqual(state.finishedGame.player_ids, ['account', 'opponent'], 'the result keeps every seat');
    assert.equal(state.lobby.host_id, 'lobbyMate', 'the next seat becomes host');
    assert.deepEqual(state.lobby.player_ids, ['lobbyMate']);
    assert.deepEqual(
      state.lobbySeats.map(({ user_id: uid, order_id: order }) => [uid, order]),
      [['lobbyMate', 0]],
      'its lobby seat is gone and the rest renumbered'
    );

    afterApply = await readDocs(seededPaths(seed));
  });

  it('a second run finds no such account, exits 1 and changes nothing', async () => {
    const { account } = seed;
    for (const [args, refusal] of [
      [['--uid', account.uid, '--apply', '--project', PROJECT_ID], noSuchUid(account.uid)],
      [
        ['--email', contact.email, '--apply', '--project', PROJECT_ID],
        `refused: no such account: no sign-in account has email ${maskedEmail(contact.email)}.\n`,
      ],
      [
        ['--phone', contact.phone, '--project', PROJECT_ID],
        `refused: no such account: no sign-in account has phone ${maskedPhone(contact.phone)}.\n`,
      ],
    ]) {
      const result = runScript([...args, '--expect-name', CODE]);
      assert.equal(result.status, 1, `${args[0]}: ${result.stderr}`);
      assert.equal(result.stderr, refusal);
    }
    assertUnchanged(afterApply, await readDocs(seededPaths(seed)));
  });

  it('the check by uid finds a profile an app still signed in wrote again, and it can be deleted by its new name', async () => {
    const { account, finished } = seed;
    // What the Android app writes when it opens with the deleted account's
    // ID token still valid, and finds no profile.
    await h.db.doc(`users/${account.uid}`).set({ display_name: 'Player', friend_ids: [], created_at: Timestamp.now() });
    await h.db.doc(`users/${account.uid}/private/data`).set({ email: contact.email, phone_number: contact.phone });

    const byEmail = runScript(['--email', contact.email, '--expect-name', CODE, '--project', PROJECT_ID]);
    assert.equal(byEmail.status, 1, byEmail.stderr);
    assert.equal(
      byEmail.stderr,
      `refused: no such account: no sign-in account has email ${maskedEmail(contact.email)}.\n`,
      '--email looks in Auth, where the account is gone, so it cannot see the profile'
    );

    const byUid = runScript(['--uid', account.uid, '--expect-name', CODE, '--project', PROJECT_ID]);
    assert.equal(byUid.status, 1, byUid.stderr);
    assert.deepEqual(byUid.stdout.split('\n').slice(5), [
      'account:',
      row('uid:', account.uid),
      row('display name:', '"Player"'),
      row('sign-in providers:', 'none: no sign-in account'),
      row('email:', 'none'),
      row('phone:', 'none'),
      '',
      '',
    ]);
    assert.equal(byUid.stderr, `refused: the display name is "Player", not ${JSON.stringify(CODE)}. It must match --expect-name exactly.\n`);

    const again = runScript(['--uid', account.uid, '--expect-name', 'Player', '--apply', '--project', PROJECT_ID]);
    assert.equal(again.status, 0, again.stderr);
    const lines = again.stdout.split('\n');
    assert.deepEqual(lines.slice(lines.indexOf(`deleted ${account.uid}:`)), [
      `deleted ${account.uid}:`,
      row('left waiting lobbies:', '0'),
      row('anonymized its seats in games:', `1  games/${finished.gameId}`),
      row("took it off friends' lists:", '0'),
      row('deleted friend requests:', '0'),
      row('deleted the profile:', `users/${account.uid} and everything under it`),
      row('deleted the sign-in account:', 'no, it was already deleted'),
      ...checkLater(account.uid, AFTER_EARLIER_SIGN_IN_DELETE),
      '',
    ]);
    const state = await endState(seed);
    assert.equal(state.profile, null, 'the profile must be deleted again');
    assert.equal(state.privateData, null, 'the private doc must be deleted again');
    assert.deepEqual(state.profileCollections, []);

    const last = runScript(['--uid', account.uid, '--expect-name', 'Player', '--project', PROJECT_ID]);
    assert.equal(last.status, 1, last.stderr);
    assert.equal(last.stderr, noSuchUid(account.uid));
  });
});

describe('delete-account script — refusals', () => {
  it('refuses a display name that is not exactly the code, and changes nothing', async () => {
    // A guest: no email or phone to find it by, so it is named by uid.
    const guest = await h.createUser(CODE);
    const seed = await seedAccount(guest, uniqueContact('guest'));
    const before = await readDocs(seededPaths(seed));

    for (const [code, extra] of [
      ['Lantern-4822', []],
      ['lantern-4821', ['--apply', '--project', PROJECT_ID]],
      [`${CODE} `, ['--apply', '--project', PROJECT_ID]],
    ]) {
      const result = runScript(['--uid', guest.uid, '--expect-name', code, ...extra]);
      assert.equal(result.status, 1, `${JSON.stringify(code)}: ${result.stderr}`);
      assert.equal(
        result.stderr,
        `refused: the display name is ${JSON.stringify(CODE)}, not ${JSON.stringify(code)}. ` +
          'It must match --expect-name exactly.\n'
      );
      assert.deepEqual(result.stdout.split('\n').slice(5), [
        'account:',
        row('uid:', guest.uid),
        row('display name:', JSON.stringify(CODE)),
        row('sign-in providers:', 'none (guest)'),
        row('email:', 'none'),
        row('phone:', 'none'),
        '',
        '',
      ]);
    }

    assertUnchanged(before, await readDocs(seededPaths(seed)));
    assert.ok(await h.getAuthUser(guest.uid), 'the sign-in account must survive');
  });

  it('masks a display name with "@" in it, as an old email account can still have, and compares it whole', async () => {
    const contact = uniqueContact('legacy');
    const account = await createSignInAccount(contact.email, contact);
    const secrets = [contact.email, contact.email.split('@')[0]];

    // The name old builds set, and one reset-email-display-names.js leaves
    // alone because of its trailing space.
    for (const name of [contact.email, `${contact.email} `]) {
      await h.db.doc(`users/${account.uid}`).update({ display_name: name });
      const shown = `"${name[0]}***${name.slice(name.indexOf('@'))}" (masked: it contains "@")`;

      const result = runScript(['--uid', account.uid, '--expect-name', CODE, '--project', PROJECT_ID]);
      assert.equal(result.status, 1, result.stderr);
      assert.equal(result.stdout.split('\n')[7], row('display name:', shown));
      assert.equal(
        result.stderr,
        `refused: the display name is ${shown}, not ${JSON.stringify(CODE)}. It must match --expect-name exactly.\n`
      );
      for (const secret of secrets) {
        assert.ok(!result.stdout.includes(secret), `stdout must not contain ${secret}`);
        assert.ok(!result.stderr.includes(secret), `stderr must not contain ${secret}`);
      }
    }

    // Masking is only how it is shown: the check is on the name itself.
    const named = runScript(['--uid', account.uid, '--expect-name', `${contact.email} `, '--project', PROJECT_ID]);
    assert.equal(named.status, 0, named.stderr);
    for (const secret of secrets) {
      assert.ok(!named.stdout.includes(secret), `stdout must not contain ${secret}`);
    }
    assert.ok(await h.getAuthUser(account.uid), 'the sign-in account must survive');
  });

  it('--expect-name - reads the name from the first line of stdin, exactly as written there', async () => {
    // A name an old build gave an email account, which step 4 may find on a
    // profile an app wrote again: the runbook has it given on stdin.
    const contact = uniqueContact('stdin');
    const name = `${contact.email} `;
    const account = await createSignInAccount(name, contact);
    const named = ['--uid', account.uid, '--expect-name', '-', '--project', PROJECT_ID];
    const shown = `"${name[0]}***${name.slice(name.indexOf('@'))}" (masked: it contains "@")`;
    const runs = [];

    // The first line, with or without its line ending, and nothing after it.
    // The trailing space counts: the name matches only because it is kept.
    for (const input of [`${name}\n`, name, `${name}\r\n${CODE}\n`]) {
      const result = runScriptWithInput(input, named);
      runs.push(result);
      assert.equal(result.status, 0, `${JSON.stringify(input)}: ${result.stderr}`);
      assert.equal(result.stderr, '');
      assert.equal(result.stdout.split('\n')[7], row('display name:', shown));
    }

    const other = runScriptWithInput(`${CODE}\n${name}\n`, named);
    runs.push(other);
    assert.equal(other.status, 1, other.stderr);
    assert.equal(
      other.stderr,
      `refused: the display name is ${shown}, not ${JSON.stringify(CODE)}. It must match --expect-name exactly.\n`
    );

    // With no name to read, it stops before printing or reading anything.
    for (const input of [undefined, '', '\n']) {
      const result = runScriptWithInput(input, [...named, '--apply']);
      runs.push(result);
      assert.equal(result.status, 2, `${JSON.stringify(input)}: ${result.stderr}`);
      assert.equal(result.stdout, '');
      assert.match(result.stderr, /^error: --expect-name - found no name on the first line of stdin\./);
    }
    assert.ok(await h.getAuthUser(account.uid), 'the sign-in account must survive');

    const applied = runScriptWithInput(`${name}\n`, [...named, '--apply']);
    runs.push(applied);
    assert.equal(applied.status, 0, applied.stderr);
    assert.equal(await h.getAuthUser(account.uid), null, 'the sign-in account must be deleted');
    assert.equal((await h.db.doc(`users/${account.uid}`).get()).exists, false, 'the profile must be deleted');

    for (const result of runs) {
      for (const secret of [contact.email, contact.email.split('@')[0]]) {
        assert.ok(!result.stdout.includes(secret), `stdout must not contain ${secret}`);
        assert.ok(!result.stderr.includes(secret), `stderr must not contain ${secret}`);
      }
    }
  });

  it('refuses an account that has a sign-in account but no profile, and changes nothing', async () => {
    const contact = uniqueContact('profileless');
    const record = await adminAuth.createUser({
      email: contact.email,
      phoneNumber: contact.phone,
      password: 'emulator-only-password',
    });

    for (const selector of [['--email', contact.email], ['--uid', record.uid]]) {
      const result = runScript([...selector, '--expect-name', CODE, '--apply', '--project', PROJECT_ID]);
      assert.equal(result.status, 1, `${selector[0]}: ${result.stderr}`);
      assert.equal(result.stderr, noProfile(record.uid));
      assert.deepEqual(result.stdout.split('\n').slice(7, 9), [
        row('display name:', `none: users/${record.uid} doesn't exist`),
        row('documents left under it:', '0'),
      ]);
    }

    assert.ok(await h.getAuthUser(record.uid), 'the sign-in account must survive');
    assert.equal((await h.db.doc(`users/${record.uid}`).get()).exists, false, 'no profile may be written');
  });

  it('refuses while the account is in, or hosts, a game in progress, and changes nothing', async () => {
    const contact = uniqueContact('midgame');
    const player = await createSignInAccount(CODE, contact);
    const seed = await seedAccount(player, contact);
    const other = await h.createUser('Mid Game Opponent');
    const live = await h.seedGame({ users: [other, player], state: 'in_progress' });
    // Hosts a live game without holding a seat or a player_ids entry in it.
    const host = await createSignInAccount(CODE, uniqueContact('unseated'));
    const a = await h.createUser('Unseated Host Player A');
    const b = await h.createUser('Unseated Host Player B');
    const hosted = await h.seedGame({ users: [a, b], host, state: 'in_progress' });
    const before = await readDocs(seededPaths(seed));

    for (const [account, game, extra] of [
      [player, live, []],
      [player, live, ['--apply', '--project', PROJECT_ID]],
      [host, hosted, ['--apply', '--project', PROJECT_ID]],
    ]) {
      const result = runScript(['--uid', account.uid, '--expect-name', CODE, ...extra]);
      assert.equal(result.status, 1, result.stderr);
      assert.equal(
        result.stderr,
        `refused: ${account.uid} is in, or hosts, a game in progress: games/${game.gameId}. It can be ` +
          'deleted once that game ends; a game with no activity for 24 hours is removed automatically.\n'
      );
    }

    assertUnchanged(before, await readDocs(seededPaths(seed)));
    assert.ok(await h.getAuthUser(player.uid), 'the sign-in account must survive');
    assert.ok(await h.getAuthUser(host.uid), "the host's sign-in account must survive");
    assert.ok((await h.db.doc(`users/${host.uid}`).get()).exists, "the host's profile must survive");
    assert.equal((await h.getGame(hosted.gameId)).host_id, host.uid);
    assert.deepEqual((await h.getGame(live.gameId)).player_ids, [other.uid, player.uid]);
  });

  it('refuses an unknown uid, email address or phone number', () => {
    const missing = uniqueContact('missing');
    for (const [args, refusal] of [
      [['--uid', 'no-such-uid-0451'], noSuchUid('no-such-uid-0451')],
      [['--email', missing.email], `refused: no such account: no sign-in account has email ${maskedEmail(missing.email)}.\n`],
      [['--phone', missing.phone], `refused: no such account: no sign-in account has phone ${maskedPhone(missing.phone)}.\n`],
    ]) {
      const result = runScript([...args, '--expect-name', CODE, '--apply', '--project', PROJECT_ID]);
      assert.equal(result.status, 1, result.stderr);
      assert.equal(result.stderr, refusal);
    }
  });

  it('stops with a usage error, before printing or reading anything, on a bad command line', async () => {
    const contact = uniqueContact('usage');
    const account = await createSignInAccount(CODE, contact);
    const named = ['--uid', account.uid, '--expect-name', CODE];

    for (const [args, env, message] of [
      [[...named, '--apply'], {}, /^error: --apply needs --project <id>\./],
      [['--expect-name', CODE, '--project', PROJECT_ID], {}, /^error: Pass exactly one of --uid, --email or --phone\./],
      [[...named, '--email', contact.email, '--project', PROJECT_ID], {}, /^error: Pass exactly one of/],
      [['--uid', account.uid, '--project', PROJECT_ID], {}, /^error: --expect-name <code> is required/],
      [['--uid', account.uid, '--expect-name', '--apply', '--project', PROJECT_ID], {}, /^error: --expect-name requires a value\./],
      [['--uid', 'u'.repeat(129), '--expect-name', CODE], {}, /^error: --uid takes a uid, which is at most 128 characters long\./],
      [['--email', `${contact.email.split('@')[0]}@`, '--expect-name', CODE], {}, /^error: --email takes an email address/],
      [['--phone', '6505550000', '--expect-name', CODE], {}, /^error: --phone takes an international number/],
      [
        [...named, '--apply', '--project', PROJECT_ID],
        { FIREBASE_AUTH_EMULATOR_HOST: undefined },
        /^error: FIRESTORE_EMULATOR_HOST is set but FIREBASE_AUTH_EMULATOR_HOST isn't/,
      ],
    ]) {
      const result = runScript(args, env);
      assert.equal(result.status, 2, `${args.join(' ')}: ${result.stderr}`);
      assert.equal(result.stdout, '', 'nothing may be printed before the command line is accepted');
      assert.match(result.stderr, message);
    }

    assert.ok(await h.getAuthUser(account.uid), 'the sign-in account must survive');
    assert.equal((await h.db.doc(`users/${account.uid}`).get()).get('display_name'), CODE);
  });
});

describe('delete-account script — a failure is not a refusal', () => {
  it('exits 3, having written nothing, when Auth cannot be reached', async () => {
    const contact = uniqueContact('unreachable');
    const account = await createSignInAccount(CODE, contact);
    const before = await readDocs([`users/${account.uid}`]);

    // Nothing listens on port 1: the lookup fails before anything is read.
    const result = runScript(['--uid', account.uid, '--expect-name', CODE, '--apply', '--project', PROJECT_ID], {
      FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:1',
    });

    assert.equal(result.status, 3, result.stderr);
    assert.ok(
      result.stderr.endsWith(
        '\nfailed: nothing was written. Fix what the error above names (often credentials, permissions ' +
          'or the network), then run the same command again.\n'
      ),
      result.stderr
    );
    assertUnchanged(before, await readDocs([`users/${account.uid}`]));
    assert.ok(await h.getAuthUser(account.uid), 'the sign-in account must survive');
  });

  it('exits 3 when deleting the sign-in account fails; once it is deleted in the console, it is done', async () => {
    const contact = uniqueContact('signin');
    const seed = await seedAccount(await createSignInAccount(CODE, contact), contact);
    const { account } = seed;
    const apply = ['--uid', account.uid, '--expect-name', CODE, '--apply', '--project', PROJECT_ID];

    const failed = runScriptWithFault('fail-sign-in-delete', account, apply);
    assert.equal(failed.status, 3, failed.stderr);
    assert.ok(failed.stderr.endsWith(`\n${stoppedPartWay(account.uid)}`), failed.stderr);
    // Every Firestore step ran; the sign-in account is all that is left.
    const state = await endState(seed);
    assert.equal(state.signIn, true);
    assert.equal(state.profile, null);
    assert.equal(state.privateData, null);
    assert.deepEqual(state.people.friendA.friend_ids, []);
    assert.equal(state.sentRequest, null);
    assert.equal(state.finishedSeats[0].display_name, DELETED_NAME);
    assert.deepEqual(state.lobby.player_ids, ['lobbyMate']);

    // Running it again can't check the code without the profile, so it
    // refuses and says how to finish.
    const retry = runScript(apply);
    assert.equal(retry.status, 1, retry.stderr);
    assert.equal(retry.stderr, noProfile(account.uid));
    assert.ok(await h.getAuthUser(account.uid), 'the refused run must not delete the sign-in account');

    await adminAuth.deleteUser(account.uid); // what the console's Delete account does
    const done = runScript(apply);
    assert.equal(done.status, 1, done.stderr);
    assert.equal(done.stderr, noSuchUid(account.uid));
  });

  it('exits 3 when the friend request batch fails, and running it again finishes the deletion', async () => {
    const contact = uniqueContact('batch');
    const seed = await seedAccount(await createSignInAccount(CODE, contact), contact);
    const { account, finished } = seed;
    const apply = ['--uid', account.uid, '--expect-name', CODE, '--apply', '--project', PROJECT_ID];

    const failed = runScriptWithFault('fail-friend-request-batch', account, apply);
    assert.equal(failed.status, 3, failed.stderr);
    assert.ok(failed.stderr.endsWith(`\n${stoppedPartWay(account.uid)}`), failed.stderr);
    // Steps 2 and 3 ran; the failed batch wrote nothing, and nothing after it ran.
    let state = await endState(seed);
    assert.deepEqual(state.lobby.player_ids, ['lobbyMate'], 'it left the lobby');
    assert.equal(state.finishedSeats[0].display_name, DELETED_NAME, 'it anonymized the seat');
    assert.deepEqual(state.people.friendA.friend_ids, ['account'], 'friends must still be linked');
    assert.ok(state.sentRequest, 'the request it sent must still exist');
    assert.ok(state.receivedRequest, 'the request it received must still exist');
    assert.equal(state.profile.display_name, CODE);
    assert.equal(state.signIn, true);

    const retry = runScript(apply);
    assert.equal(retry.status, 0, retry.stderr);
    const lines = retry.stdout.split('\n');
    assert.deepEqual(lines.slice(lines.indexOf(`deleted ${account.uid}:`)), [
      `deleted ${account.uid}:`,
      row('left waiting lobbies:', '0'),
      row('anonymized its seats in games:', `1  games/${finished.gameId}`),
      row("took it off friends' lists:", '2'),
      row('deleted friend requests:', '2'),
      row('deleted the profile:', `users/${account.uid} and everything under it`),
      row('deleted the sign-in account:', 'yes'),
      ...checkLater(account.uid),
      '',
    ]);
    state = await endState(seed);
    assert.equal(state.profile, null);
    assert.equal(state.privateData, null);
    assert.equal(state.signIn, false);
    assert.deepEqual(state.people.friendA.friend_ids, []);
    assert.deepEqual(state.people.friendB.friend_ids, []);
    assert.equal(state.sentRequest, null);
    assert.equal(state.receivedRequest, null);
  });
});

describe('delete-account script — what a deletion that stops in step 5 leaves', () => {
  // recursiveDelete deletes users/{uid} even when deleting a document under
  // it fails, so a failed step 5 can leave private/data, with the email
  // address, phone number and push token, under a profile that is gone.
  const contact = uniqueContact('leftover');
  let seed;
  let leftover; // users/{uid}/private/data
  let apply;

  before(async () => {
    seed = await seedAccount(await createSignInAccount(CODE, contact), contact);
    leftover = `users/${seed.account.uid}/private/data`;
    apply = ['--uid', seed.account.uid, '--expect-name', CODE, '--apply', '--project', PROJECT_ID];
  });

  it('exits 3 when step 5 leaves private/data behind, and the next run names it', async () => {
    const { account } = seed;

    const failed = runScriptWithFault('fail-delete-under-profile', account, apply);
    assert.equal(failed.status, 3, failed.stderr);
    assert.ok(failed.stderr.endsWith(`\n${stoppedPartWay(account.uid)}`), failed.stderr);
    const state = await endState(seed);
    assert.equal(state.profile, null, 'users/{uid} itself is deleted');
    assert.deepEqual(
      state.privateData,
      { email: contact.email, phone_number: contact.phone, fcm_token: 'fcm-token' },
      'private/data is left behind'
    );
    assert.equal(state.signIn, true, 'step 6 never ran');

    for (const [selector, uidRow] of [
      [['--uid', account.uid], account.uid],
      [['--email', contact.email], `${account.uid} (found by email ${maskedEmail(contact.email)})`],
    ]) {
      const result = runScript([...selector, '--expect-name', CODE, '--project', PROJECT_ID]);
      assert.equal(result.status, 1, `${selector[0]}: ${result.stderr}`);
      assert.equal(result.stderr, noProfile(account.uid, [leftover]));
      assert.deepEqual(result.stdout.split('\n').slice(5), [
        'account:',
        row('uid:', uidRow),
        row('display name:', `none: users/${account.uid} doesn't exist`),
        row('documents left under it:', `1  ${leftover}`),
        row('sign-in providers:', 'password, phone'),
        row('email:', maskedEmail(contact.email)),
        row('phone:', maskedPhone(contact.phone)),
        '',
        '',
      ]);
    }
  });

  it('keeps the name check while the sign-in account exists: --apply is refused and changes nothing', async () => {
    const { account } = seed;
    const before = await readDocs(seededPaths(seed));

    for (const code of [CODE, 'Lantern-4822']) {
      const result = runScript(['--uid', account.uid, '--expect-name', code, '--apply', '--project', PROJECT_ID]);
      assert.equal(result.status, 1, `${code}: ${result.stderr}`);
      assert.equal(result.stderr, noProfile(account.uid, [leftover]));
      assert.ok(!result.stdout.includes(`deleting ${account.uid}`), 'it must stop before deleting anything');
    }

    assertUnchanged(before, await readDocs(seededPaths(seed)));
    assert.ok(await h.getAuthUser(account.uid), 'the sign-in account must survive');
  });

  it('once the sign-in account is deleted, --apply by uid deletes what is left without a name check', async () => {
    const { account, finished } = seed;
    await adminAuth.deleteUser(account.uid); // what the console's Delete account does

    // No account is left whose name could be checked, so any code passes.
    const before = await readDocs(seededPaths(seed));
    const dryRun = runScript(['--uid', account.uid, '--expect-name', 'Lantern-4822', '--project', PROJECT_ID]);
    assert.equal(dryRun.status, 0, dryRun.stderr);
    assert.equal(dryRun.stderr, '');
    assert.deepEqual(dryRun.stdout.split('\n').slice(5), [
      'account:',
      row('uid:', account.uid),
      row('display name:', `none: users/${account.uid} doesn't exist`),
      row('documents left under it:', `1  ${leftover}`),
      row('sign-in providers:', 'none: no sign-in account'),
      row('email:', 'none'),
      row('phone:', 'none'),
      '',
      LEFTOVERS_ONLY,
      '',
      'deleting it would:',
      row('leave waiting lobbies:', '0'),
      row('anonymize its seats in games:', `1  games/${finished.gameId}`),
      row("take it off friends' lists:", '0'),
      row('delete friend requests:', '0'),
      row('delete profile documents:', `1  ${leftover}`),
      row('delete the sign-in account:', '0'),
      '',
      'DRY RUN — nothing was written. Re-run with --apply --project <id> to delete this account.',
      '',
    ]);
    assertUnchanged(before, await readDocs(seededPaths(seed)));

    const done = runScript(apply);
    assert.equal(done.status, 0, done.stderr);
    assert.equal(done.stderr, '');
    const lines = done.stdout.split('\n');
    assert.deepEqual(lines.slice(lines.indexOf(`deleting ${account.uid} from ${PROJECT_ID} …`)), [
      `deleting ${account.uid} from ${PROJECT_ID} …`,
      `deleted ${account.uid}:`,
      row('left waiting lobbies:', '0'),
      row('anonymized its seats in games:', `1  games/${finished.gameId}`),
      row("took it off friends' lists:", '0'),
      row('deleted friend requests:', '0'),
      row('deleted the profile:', `users/${account.uid} and everything under it`),
      row('deleted the sign-in account:', 'no, it was already deleted'),
      ...checkLater(account.uid, AFTER_EARLIER_SIGN_IN_DELETE),
      '',
    ]);

    // Nothing of the account is left: the state a run that never failed leaves.
    const state = await endState(seed);
    assert.equal(state.privateData, null, 'private/data must be deleted');
    assert.deepEqual(state.profileCollections, [], 'nothing may be left under users/{uid}');
    assert.equal(state.profile, null);
    assert.equal(state.signIn, false);
    assert.deepEqual(state.people.friendA.friend_ids, []);
    assert.deepEqual(state.people.friendB.friend_ids, []);
    assert.equal(state.sentRequest, null);
    assert.equal(state.receivedRequest, null);
    assert.equal(state.finishedSeats[0].display_name, DELETED_NAME);
    assert.deepEqual(state.lobby.player_ids, ['lobbyMate']);

    const check = runScript(['--uid', account.uid, '--expect-name', CODE, '--project', PROJECT_ID]);
    assert.equal(check.status, 1, check.stderr);
    assert.equal(check.stderr, noSuchUid(account.uid));
  });
});

describe('delete-account script — a lobby that starts during the deletion', () => {
  it('refuses, having written nothing, when a lobby it is in starts after the checks', async () => {
    const contact = uniqueContact('raced');
    const seed = await seedAccount(await createSignInAccount(CODE, contact), contact);
    const { account, lobby } = seed;
    const paths = seededPaths(seed).filter((docPath) => docPath !== `games/${lobby.gameId}`);
    const before = await readDocs(paths);
    const apply = ['--uid', account.uid, '--expect-name', CODE, '--apply', '--project', PROJECT_ID];

    const result = runScriptWithFault('start-lobbies-before-deleting', account, apply);

    assert.equal(result.status, 1, result.stderr);
    assert.equal(result.stderr, startedAfterCheck(account.uid));
    assert.ok(result.stdout.endsWith(`deleting ${account.uid} from ${PROJECT_ID} …\n`), 'it had passed the checks');
    assertUnchanged(before, await readDocs(paths));
    const game = await h.getGame(lobby.gameId);
    assert.equal(game.state, 'in_progress');
    assert.equal(game.host_id, account.uid);
    assert.deepEqual(game.player_ids, [account.uid, seed.people.lobbyMate.uid]);
    assert.ok(await h.getAuthUser(account.uid), 'the sign-in account must survive');
  });

  it('stops after the lobbies it has left when the next one starts, and finishes once that game ends', async () => {
    const contact = uniqueContact('twolobbies');
    const seed = await seedAccount(await createSignInAccount(CODE, contact), contact);
    const { account, lobby, finished } = seed;
    const second = await h.seedGame({ users: [await h.createUser('Second Lobby Host'), account] });
    const lobbyIds = [lobby.gameId, second.gameId];
    // Which lobby it reaches first depends on the ids, so neither is compared here.
    const paths = seededPaths(seed).filter(
      (docPath) => docPath !== `games/${lobby.gameId}` && !docPath.startsWith(`games/${lobby.gameId}/`)
    );
    const before = await readDocs(paths);
    const apply = ['--uid', account.uid, '--expect-name', CODE, '--apply', '--project', PROJECT_ID];

    const raced = runScriptWithFault('start-lobbies-before-second-leave', account, apply);
    assert.equal(raced.status, 1, raced.stderr);
    assert.equal(raced.stderr, startedAfterCheck(account.uid));
    const games = await Promise.all(lobbyIds.map((gameId) => h.getGame(gameId)));
    const left = games.filter((game) => !game.player_ids.includes(account.uid));
    const live = games.filter((game) => game.player_ids.includes(account.uid));
    assert.equal(left.length, 1, 'it left the first lobby');
    assert.equal(left[0].state, 'waiting');
    assert.equal(live.length, 1, 'it is still in the other');
    assert.equal(live[0].state, 'in_progress');
    assert.equal((await h.getPlayers(live[0].id)).filter((seat) => seat.user_id === account.uid).length, 1);
    assertUnchanged(before, await readDocs(paths));
    assert.ok(await h.getAuthUser(account.uid), 'the sign-in account must survive');

    await h.patchGame(live[0].id, { state: 'finished' });
    const done = runScript(apply);
    assert.equal(done.status, 0, done.stderr);
    const lines = done.stdout.split('\n');
    const seatsLine = lines.find((line) => line.startsWith(row('anonymized its seats in games:', '')));
    assert.deepEqual(
      seatsLine.slice(row('anonymized its seats in games:', '2  ').length).split(', ').sort(),
      [`games/${finished.gameId}`, `games/${live[0].id}`].sort()
    );
    assert.ok(lines.includes(row('left waiting lobbies:', '0')));
    assert.ok(lines.includes(row('deleted the sign-in account:', 'yes')));
    const seat = (await h.getPlayers(live[0].id)).find((player) => player.user_id === account.uid);
    assert.equal(seat.display_name, DELETED_NAME, 'its seat in the game that ended is anonymized');
    assert.equal(await h.getAuthUser(account.uid), null);
    assert.equal((await h.db.doc(`users/${account.uid}`).get()).exists, false);
  });
});

describe('delete-account script — where it reads and writes', () => {
  it('reads and deletes only in the --project it names, whatever project the environment names', async () => {
    const contact = uniqueContact('elsewhere');
    const account = await createSignInAccount(CODE, contact);
    // Every place an initializeApp() without options would take a project
    // from. emulators:exec sets FIREBASE_CONFIG to the suite's own project,
    // and that comes first.
    const env = {
      FIREBASE_CONFIG: JSON.stringify({ projectId: 'demo-elsewhere' }),
      GOOGLE_CLOUD_PROJECT: 'demo-elsewhere',
      GCLOUD_PROJECT: 'demo-elsewhere',
    };
    const named = ['--uid', account.uid, '--expect-name', CODE, '--project', PROJECT_ID];

    const dryRun = runScript(named, env);
    assert.equal(dryRun.status, 0, dryRun.stderr);
    const lines = dryRun.stdout.split('\n');
    assert.deepEqual(lines.slice(0, 5), header('DRY RUN (no writes)'));
    assert.equal(lines[7], row('display name:', JSON.stringify(CODE)), `it must find the account in ${PROJECT_ID}`);

    const applied = runScript([...named, '--apply'], env);
    assert.equal(applied.status, 0, applied.stderr);
    assert.equal(await h.getAuthUser(account.uid), null, `the sign-in account must be deleted from ${PROJECT_ID}`);
    assert.equal((await h.db.doc(`users/${account.uid}`).get()).exists, false, `the profile must be deleted from ${PROJECT_ID}`);
  });
});

describe('delete-account script — finding the account by email or phone', () => {
  it('--email and --phone find the account that signs in with them', async () => {
    const first = uniqueContact('first');
    const second = uniqueContact('second');
    const a = await createSignInAccount('Lookup-1111', first);
    const b = await createSignInAccount('Lookup-2222', second);

    for (const [args, account, name, how] of [
      [['--email', first.email], a, 'Lookup-1111', `email ${maskedEmail(first.email)}`],
      [['--phone', first.phone], a, 'Lookup-1111', `phone ${maskedPhone(first.phone)}`],
      [['--email', second.email], b, 'Lookup-2222', `email ${maskedEmail(second.email)}`],
      [['--phone', second.phone], b, 'Lookup-2222', `phone ${maskedPhone(second.phone)}`],
    ]) {
      const result = runScript([...args, '--expect-name', name, '--project', PROJECT_ID]);
      assert.equal(result.status, 0, result.stderr);
      const lines = result.stdout.split('\n');
      assert.equal(lines[6], row('uid:', `${account.uid} (found by ${how})`));
      assert.equal(lines[7], row('display name:', JSON.stringify(name)));
    }
  });
});
