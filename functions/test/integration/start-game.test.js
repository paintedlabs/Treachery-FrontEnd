/**
 * Integration tests for the startGame callable.
 *
 * Why these exist: a P0 shipped where hosts couldn't start 2+ player games
 * because startGame's preconditions blocked the call. A test that just calls
 * startGame on a default 2-player setup would have caught it before merge.
 *
 * Run: npm run test:integration
 *   (wraps `node --test` in `firebase emulators:exec --only firestore` so the
 *   Firestore emulator is up while the test executes and torn down after.)
 */

const assert = require("node:assert/strict");
const { describe, it, after, beforeEach } = require("node:test");

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "demo-test";

const test = require("firebase-functions-test")();
const admin = require("firebase-admin");
const myFunctions = require("../../index");

const startGame = test.wrap(myFunctions.startGame);
const db = admin.firestore();

async function clearAllGames() {
  const games = await db.collection("games").listDocuments();
  await Promise.all(
    games.map(async (gameRef) => {
      const players = await gameRef.collection("players").listDocuments();
      await Promise.all(players.map((p) => p.delete()));
      await gameRef.delete();
    })
  );
}

async function seedWaitingGame({ gameId, hostUid, playerCount, gameMode = "treachery" }) {
  const playerIds = Array.from({ length: playerCount }, (_, i) =>
    i === 0 ? hostUid : `guest-${i}`
  );
  await db.doc(`games/${gameId}`).set({
    code: "TEST",
    host_id: hostUid,
    state: "waiting",
    max_players: 8,
    starting_life: 40,
    player_ids: playerIds,
    game_mode: gameMode,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });
  for (let i = 0; i < playerCount; i++) {
    await db.collection(`games/${gameId}/players`).doc(`p${i}`).set({
      user_id: playerIds[i],
      order_id: i,
      display_name: i === 0 ? "Host" : `Guest ${i}`,
      role: null,
      identity_card_id: null,
      life_total: 40,
      is_eliminated: false,
      is_unveiled: false,
      joined_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
}

describe("startGame", () => {
  beforeEach(async () => {
    await clearAllGames();
  });

  after(() => test.cleanup());

  it("starts a 2-player treachery game with no per-player setup beyond defaults", async () => {
    await seedWaitingGame({ gameId: "g1", hostUid: "host", playerCount: 2 });

    await startGame({ data: { gameId: "g1" }, auth: { uid: "host" } });

    const game = await db.doc("games/g1").get();
    assert.equal(game.data().state, "in_progress");
  });

  it("assigns roles per the 4-player treachery distribution", async () => {
    await seedWaitingGame({ gameId: "g2", hostUid: "host", playerCount: 4 });

    await startGame({ data: { gameId: "g2" }, auth: { uid: "host" } });

    const players = await db.collection("games/g2/players").get();
    const roles = players.docs.map((d) => d.data().role).sort();
    assert.deepEqual(roles, ["assassin", "assassin", "leader", "traitor"]);
  });

  it("rejects when caller is not the host", async () => {
    await seedWaitingGame({ gameId: "g3", hostUid: "host", playerCount: 2 });

    await assert.rejects(
      () => startGame({ data: { gameId: "g3" }, auth: { uid: "intruder" } }),
      /Only the host can start the game/
    );
  });

  it("rejects when the game is already in_progress", async () => {
    await seedWaitingGame({ gameId: "g4", hostUid: "host", playerCount: 2 });
    await db.doc("games/g4").update({ state: "in_progress" });

    await assert.rejects(
      () => startGame({ data: { gameId: "g4" }, auth: { uid: "host" } }),
      /Game has already started/
    );
  });

  it("rejects unauthenticated callers", async () => {
    await seedWaitingGame({ gameId: "g5", hostUid: "host", playerCount: 2 });

    await assert.rejects(
      () => startGame({ data: { gameId: "g5" } }),
      /Must be signed in/
    );
  });
});
