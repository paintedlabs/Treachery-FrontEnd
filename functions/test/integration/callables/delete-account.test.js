'use strict';

/**
 * INTEGRATION: exports.deleteAccount (functions/index.js)
 *
 * In-app account deletion (App Store Guideline 5.1.1(v)). Every user in this
 * file comes from h.createUser(), never the shared h.getUsers() pool: a
 * deleted pooled account would break every later test that reuses it, and
 * fresh friends and table-mates keep each test's friend lists and seats its
 * own.
 */

const { describe, it, after } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

after(async () => {
  await h.shutdown();
});

const DELETED_NAME = 'Deleted player';

/** The profile doc's data, or null once it is gone. */
async function getProfile(uid) {
  const snap = await h.db.doc(`users/${uid}`).get();
  return snap.exists ? snap.data() : null;
}

async function exists(ref) {
  return (await ref.get()).exists;
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

describe('deleteAccount — preconditions', () => {
  it('rejects an unauthenticated caller', async () => {
    await h.expectHttpsError(
      h.unauthenticatedCaller()('deleteAccount', {}),
      'unauthenticated'
    );
  });

  it('refuses while the caller is in a game in progress, and deletes nothing', async () => {
    const user = await h.createUser('Mid Game');
    const friend = await h.createUser('Mid Game Friend');
    const other = await h.createUser('Mid Game Opponent');
    await befriend(user, friend);
    const sent = await seedFriendRequest(user, other);
    const received = await seedFriendRequest(other, user);
    const privateRef = h.db.doc(`users/${user.uid}/private/data`);
    await privateRef.set({ email: 'mid-game@example.com' });
    const lobby = await h.seedGame({ users: [user, other] });
    const finished = await h.seedGame({
      users: [user, other],
      state: 'finished',
      playerOverrides: { 0: { commander_name: 'Atraxa' } },
    });
    await h.seedGame({ users: [other, user], state: 'in_progress' });

    const err = await h.expectHttpsError(
      user.call('deleteAccount', {}),
      'failed-precondition'
    );
    // The clients show this message verbatim.
    assert.match(err.message, /in progress/i);
    assert.match(err.message, /once that game ends/i);

    assert.ok(await getProfile(user.uid), 'the profile must survive');
    assert.ok(await exists(privateRef), 'the private doc must survive');
    assert.ok(await h.getAuthUser(user.uid), 'the sign-in account must survive');
    assert.ok(
      (await getProfile(friend.uid)).friend_ids.includes(user.uid),
      "the friend's list must still hold the caller"
    );
    assert.ok(await exists(sent), 'the sent friend request must survive');
    assert.ok(await exists(received), 'the received friend request must survive');

    const g = await h.getGame(lobby.gameId);
    assert.equal(g.host_id, user.uid, 'the caller must still host the lobby');
    assert.deepEqual(g.player_ids, [user.uid, other.uid]);
    assert.equal((await h.getPlayers(lobby.gameId)).length, 2);

    const seat = await h.getPlayer(finished.gameId, 'p0');
    assert.equal(seat.display_name, 'Mid Game', 'the finished seat must not be anonymized');
    assert.equal(seat.commander_name, 'Atraxa');
  });

  it('refuses while the caller hosts a game in progress without a seat in it', async () => {
    // The rules let a host delete their own seat while the lobby waits, and
    // startGame then rebuilds player_ids from the seats, so the host is off
    // player_ids yet still the only one who can end the game (endGame is
    // host-only).
    const host = await h.createUser('Unseated Host');
    const a = await h.createUser('Unseated Host Player A');
    const b = await h.createUser('Unseated Host Player B');
    const game = await h.seedGame({ users: [host, a, b], gameMode: 'none' });
    await h.db.doc(`games/${game.gameId}/players/p0`).delete();
    await host.call('startGame', { gameId: game.gameId });
    const started = await h.getGame(game.gameId);
    assert.equal(started.state, 'in_progress');
    assert.deepEqual(started.player_ids, [a.uid, b.uid], 'precondition: the host is off player_ids');

    const err = await h.expectHttpsError(
      host.call('deleteAccount', {}),
      'failed-precondition'
    );
    assert.match(err.message, /in progress/i);

    assert.ok(await getProfile(host.uid), 'the profile must survive');
    assert.ok(await h.getAuthUser(host.uid), 'the sign-in account must survive');
    assert.equal((await h.getGame(game.gameId)).host_id, host.uid);
  });
});

describe('deleteAccount — waiting lobbies', () => {
  it('leaves a lobby the caller hosts, promoting the next player to host', async () => {
    const host = await h.createUser('Departing Host');
    const second = await h.createUser('Second Seat');
    const third = await h.createUser('Third Seat');
    const game = await h.seedGame({ users: [host, second, third] });

    assert.deepEqual(await host.call('deleteAccount', {}), { success: true });

    const g = await h.getGame(game.gameId);
    assert.ok(g, 'the lobby must survive its host leaving');
    assert.equal(g.host_id, second.uid, 'lowest remaining seat becomes host');
    assert.deepEqual(g.player_ids, [second.uid, third.uid]);

    const players = await h.getPlayers(game.gameId);
    assert.deepEqual(players.map((p) => p.user_id), [second.uid, third.uid]);
    assert.deepEqual(players.map((p) => p.order_id), [0, 1], 'seats are renumbered');
  });

  it('deletes a lobby when the caller was its last player', async () => {
    const user = await h.createUser('Last One Out');
    const game = await h.seedGame({ users: [user] });

    assert.deepEqual(await user.call('deleteAccount', {}), { success: true });

    assert.equal(await h.getGame(game.gameId), null, 'the empty lobby must be removed');
    assert.equal((await h.getPlayers(game.gameId)).length, 0);
  });

  it('is not blocked by a lobby that lists the caller without a seat', async () => {
    // The append-self rules path can add a uid to player_ids with no player
    // doc. leaveGame answers not-found for such a caller; that must not make
    // the account undeletable.
    const host = await h.createUser('Seated Host');
    const user = await h.createUser('Seatless Member');
    const game = await h.seedGame({ users: [host, user] });
    await h.db.doc(`games/${game.gameId}/players/p1`).delete();

    assert.deepEqual(await user.call('deleteAccount', {}), { success: true });

    assert.equal(await getProfile(user.uid), null);
    assert.equal(await h.getAuthUser(user.uid), null);
    const g = await h.getGame(game.gameId);
    assert.equal(g.host_id, host.uid, 'the host keeps the lobby');
    assert.deepEqual(g.player_ids, [host.uid], 'the bare player_ids entry is dropped');
    assert.deepEqual((await h.getPlayers(game.gameId)).map((p) => p.user_id), [host.uid]);
  });

  it('hands a lobby it hosts without a seat to the lowest remaining seat', async () => {
    // The rules let a host delete their own seat while the lobby waits.
    // Left as it was, host_id would name a deleted account, and nobody could
    // start the lobby or change its settings (both are host-only).
    const host = await h.createUser('Seatless Host');
    const second = await h.createUser('Seatless Host Second');
    const third = await h.createUser('Seatless Host Third');
    const game = await h.seedGame({ users: [host, second, third] });
    await h.db.doc(`games/${game.gameId}/players/p0`).delete();

    assert.deepEqual(await host.call('deleteAccount', {}), { success: true });

    const g = await h.getGame(game.gameId);
    assert.equal(g.host_id, second.uid, 'lowest remaining seat becomes host');
    assert.deepEqual(g.player_ids, [second.uid, third.uid]);
    const players = await h.getPlayers(game.gameId);
    assert.deepEqual(players.map((p) => p.user_id), [second.uid, third.uid]);
    assert.deepEqual(players.map((p) => p.order_id), [0, 1], 'seats are renumbered');
  });

  it('deletes a lobby it hosts without a seat when no seat is left', async () => {
    const host = await h.createUser('Host Of Empty Lobby');
    const game = await h.seedGame({ users: [host] });
    await h.db.doc(`games/${game.gameId}/players/p0`).delete();

    assert.deepEqual(await host.call('deleteAccount', {}), { success: true });

    assert.equal(await h.getGame(game.gameId), null, 'the empty lobby must be removed');
  });

  it('hands on a lobby it hosts without being on its player_ids', async () => {
    // Found through host_id alone.
    const host = await h.createUser('Unlisted Host');
    const member = await h.createUser('Unlisted Host Member');
    const game = await h.seedGame({ users: [member], host });

    assert.deepEqual(await host.call('deleteAccount', {}), { success: true });

    const g = await h.getGame(game.gameId);
    assert.equal(g.host_id, member.uid);
    assert.deepEqual(g.player_ids, [member.uid]);
  });
});

describe('deleteAccount — game history', () => {
  it("anonymizes the caller's seat in a finished game and keeps the result", async () => {
    const user = await h.createUser('Former Player');
    const opponent = await h.createUser('Remaining Player');
    const game = await h.seedGame({
      users: [user, opponent],
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

    assert.deepEqual(await user.call('deleteAccount', {}), { success: true });

    const seat = await h.getPlayer(game.gameId, 'p0');
    assert.equal(seat.display_name, DELETED_NAME);
    assert.equal(seat.commander_name, undefined, 'commander_name must be removed');
    assert.equal(seat.user_id, user.uid, 'user_id stays so history and stats stay coherent');
    assert.equal(seat.role, 'leader');
    assert.equal(seat.identity_card_id, 'leader_01');
    assert.equal(seat.life_total, 0);
    assert.equal(seat.is_eliminated, true);

    const theirs = await h.getPlayer(game.gameId, 'p1');
    assert.equal(theirs.display_name, 'Remaining Player', 'other seats are untouched');
    assert.equal(theirs.commander_name, 'Edgar Markov');

    const g = await h.getGame(game.gameId);
    assert.equal(g.state, 'finished');
    assert.equal(g.winning_team, 'assassin');
    assert.deepEqual(g.player_ids, [user.uid, opponent.uid], 'the result keeps every seat');
  });

  it('anonymizes the seat in a game the caller hosts without a player_ids entry', async () => {
    const user = await h.createUser('Legacy Host');
    const opponent = await h.createUser('Legacy Opponent');
    const game = await h.seedGame({
      users: [user, opponent],
      state: 'finished',
      gameFields: { player_ids: [opponent.uid] },
    });

    assert.deepEqual(await user.call('deleteAccount', {}), { success: true });

    const seat = await h.getPlayer(game.gameId, 'p0');
    assert.equal(seat.display_name, DELETED_NAME);
    assert.equal(seat.user_id, user.uid);
  });
});

describe('deleteAccount — social data', () => {
  it("removes the caller from other users' friend lists", async () => {
    const user = await h.createUser('Unfriended');
    const friend = await h.createUser('Their Friend');
    const friendOfFriend = await h.createUser('Friend Of Friend');
    await befriend(user, friend);
    await befriend(friend, friendOfFriend);

    assert.deepEqual(await user.call('deleteAccount', {}), { success: true });

    assert.deepEqual((await getProfile(friend.uid)).friend_ids, [friendOfFriend.uid]);
    assert.deepEqual(
      (await getProfile(friendOfFriend.uid)).friend_ids,
      [friend.uid],
      'links between other users are untouched'
    );
  });

  it('deletes friend requests in both directions, and only those', async () => {
    const user = await h.createUser('Requester');
    const a = await h.createUser('Request Target');
    const b = await h.createUser('Request Sender');
    const sent = await seedFriendRequest(user, a);
    const received = await seedFriendRequest(b, user, 'declined');
    const unrelated = await seedFriendRequest(a, b);

    assert.deepEqual(await user.call('deleteAccount', {}), { success: true });

    assert.equal(await exists(sent), false, 'the request the caller sent must be deleted');
    assert.equal(await exists(received), false, 'the request sent to the caller must be deleted');
    assert.equal(await exists(unrelated), true, 'requests between other users survive');
  });

  it('lets two friends delete their accounts at the same time', async () => {
    // Each run removes itself from the other's friend list while the other
    // run may be deleting that profile. This does not force the interleaving
    // that makes the unlink retry, so it pins the outcome: both succeed.
    const a = await h.createUser('Leaving Together A');
    const b = await h.createUser('Leaving Together B');
    const staying = await h.createUser('Staying Behind');
    await befriend(a, b);
    await befriend(a, staying);
    await befriend(b, staying);

    const results = await Promise.all([
      a.call('deleteAccount', {}),
      b.call('deleteAccount', {}),
    ]);

    assert.deepEqual(results, [{ success: true }, { success: true }]);
    assert.equal(await getProfile(a.uid), null);
    assert.equal(await getProfile(b.uid), null);
    assert.deepEqual((await getProfile(staying.uid)).friend_ids, []);
  });
});

describe('deleteAccount — profile and sign-in', () => {
  it('deletes the profile and its private docs', async () => {
    const user = await h.createUser('Profile Owner');
    const privateRef = h.db.doc(`users/${user.uid}/private/data`);
    await privateRef.set({ email: 'owner@example.com', fcm_token: 'fcm-token' });

    assert.deepEqual(await user.call('deleteAccount', {}), { success: true });

    assert.equal(await getProfile(user.uid), null, 'the profile must be deleted');
    assert.equal(await exists(privateRef), false, 'the private doc must be deleted');
    assert.deepEqual(
      await h.db.doc(`users/${user.uid}`).listCollections(),
      [],
      'no subcollection may be left behind'
    );
  });

  it('deletes the sign-in account', async () => {
    const user = await h.createUser('Signed In');
    assert.ok(await h.getAuthUser(user.uid), 'precondition: the account exists');

    assert.deepEqual(await user.call('deleteAccount', {}), { success: true });

    assert.equal(await h.getAuthUser(user.uid), null);
  });

  it('is idempotent: a second call succeeds too', async () => {
    const user = await h.createUser('Asked Twice');
    const opponent = await h.createUser('Asked Twice Opponent');
    const game = await h.seedGame({ users: [user, opponent], state: 'finished' });

    assert.deepEqual(await user.call('deleteAccount', {}), { success: true });
    assert.deepEqual(
      await user.call('deleteAccount', {}),
      { success: true },
      'a retry after a completed run must succeed'
    );

    assert.equal(await getProfile(user.uid), null);
    assert.equal(await h.getAuthUser(user.uid), null);
    assert.equal((await h.getPlayer(game.gameId, 'p0')).display_name, DELETED_NAME);
  });

  it('finishes the job when retried after a run that failed part-way', async () => {
    // Every step must be safe to run whatever the others have done, so the
    // retry starts from a mix: one lobby already left, the profile, private
    // doc and friend requests already gone, but a lobby seat, a finished
    // seat that still carries the name, and the sign-in account remain.
    const user = await h.createUser('Half Deleted');
    const other = await h.createUser('Half Deleted Table-mate');
    const leftLobby = await h.seedGame({ users: [other, user] });
    const lobby = await h.seedGame({ users: [user, other] });
    const finished = await h.seedGame({ users: [user, other], state: 'finished' });
    const request = await seedFriendRequest(user, other);
    await h.db.doc(`users/${user.uid}/private/data`).set({ fcm_token: 'fcm-token' });

    await user.call('leaveGame', { gameId: leftLobby.gameId });
    await request.delete();
    await h.db.recursiveDelete(h.db.doc(`users/${user.uid}`));

    assert.deepEqual(await user.call('deleteAccount', {}), { success: true });

    const left = await h.getGame(leftLobby.gameId);
    assert.equal(left.host_id, other.uid, 'the lobby left earlier is untouched');
    assert.deepEqual(left.player_ids, [other.uid]);
    const g = await h.getGame(lobby.gameId);
    assert.equal(g.host_id, other.uid, 'the remaining lobby is handed on');
    assert.deepEqual(g.player_ids, [other.uid]);
    assert.deepEqual((await h.getPlayers(lobby.gameId)).map((p) => p.user_id), [other.uid]);
    assert.equal((await h.getPlayer(finished.gameId, 'p0')).display_name, DELETED_NAME);
    assert.equal(await h.getAuthUser(user.uid), null, 'the sign-in account must be deleted');
    assert.equal(await getProfile(user.uid), null, 'nothing recreates the profile');
  });
});
