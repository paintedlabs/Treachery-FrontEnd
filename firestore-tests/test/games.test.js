/**
 * Rules under test: match /games/{gameId}  (firestore.rules ~lines 43-67)
 * plus the isOnlyAddingSelfToPlayerIds() helper (~line 120).
 */

"use strict";

const { doc, getDoc, setDoc, updateDoc, deleteDoc } = require("firebase/firestore");
const {
  seed,
  authedDb,
  anonDb,
  gameDoc,
  assertSucceeds,
  assertFails,
} = require("./helpers");

const HOST = "user_host";
const PLAYER = "user_player";
const THIRD = "user_third";
const OUTSIDER = "user_outsider";

const WAITING = "game_waiting";
const IN_PROGRESS = "game_in_progress";
const FULL = "game_full";

describe("games/{gameId}", () => {
  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, "games", WAITING),
        gameDoc(HOST, { player_ids: [HOST, PLAYER] })
      );
      await setDoc(
        doc(db, "games", IN_PROGRESS),
        gameDoc(HOST, {
          state: "in_progress",
          player_ids: [HOST, PLAYER, THIRD],
          join_code: "WXYZ",
        })
      );
      await setDoc(
        doc(db, "games", FULL),
        gameDoc(HOST, {
          max_players: 4,
          player_ids: [HOST, PLAYER, THIRD, "user_fourth"],
          join_code: "FULL",
        })
      );
    });
  });

  // ─── read ────────────────────────────────────────────────────────
  describe("read", () => {
    it("lets any signed-in user read a lobby (join-by-code flow)", async () => {
      const db = await authedDb(OUTSIDER);
      await assertSucceeds(getDoc(doc(db, "games", WAITING)));
    });

    it("denies a signed-out client", async () => {
      const db = await anonDb();
      await assertFails(getDoc(doc(db, "games", WAITING)));
    });
  });

  // ─── create ──────────────────────────────────────────────────────
  describe("create", () => {
    it("lets a user create a game they host, in the waiting state", async () => {
      const db = await authedDb(OUTSIDER);
      await assertSucceeds(
        setDoc(doc(db, "games", "game_new"), gameDoc(OUTSIDER))
      );
    });

    it("stops a user from creating a game hosted by somebody else", async () => {
      const db = await authedDb(OUTSIDER);
      await assertFails(setDoc(doc(db, "games", "game_forged"), gameDoc(HOST)));
    });

    it("stops a user from creating a game that is already in_progress", async () => {
      const db = await authedDb(OUTSIDER);
      await assertFails(
        setDoc(
          doc(db, "games", "game_started"),
          gameDoc(OUTSIDER, { state: "in_progress" })
        )
      );
    });

    it("stops a signed-out client from creating a game", async () => {
      const db = await anonDb();
      await assertFails(setDoc(doc(db, "games", "game_anon"), gameDoc(OUTSIDER)));
    });
  });

  // ─── update: host settings ───────────────────────────────────────
  describe("update (host settings)", () => {
    it("lets the host change lobby settings while waiting", async () => {
      const db = await authedDb(HOST);
      await assertSucceeds(
        updateDoc(doc(db, "games", WAITING), {
          max_players: 8,
          starting_life: 60,
          max_traitor_rarity: "rare",
        })
      );
    });

    it("stops a non-host from changing lobby settings", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(updateDoc(doc(db, "games", WAITING), { max_players: 8 }));
    });

    it("stops an outsider from changing lobby settings", async () => {
      const db = await authedDb(OUTSIDER);
      await assertFails(updateDoc(doc(db, "games", WAITING), { max_players: 8 }));
    });

    it("stops even the host from editing a game that is already in_progress", async () => {
      const db = await authedDb(HOST);
      await assertFails(
        updateDoc(doc(db, "games", IN_PROGRESS), { max_players: 8 })
      );
    });

    it("stops the host from starting the game from the client (Cloud Functions only)", async () => {
      const db = await authedDb(HOST);
      await assertFails(
        updateDoc(doc(db, "games", WAITING), { state: "in_progress" })
      );
    });

    it("stops the host from declaring a winning_team from the client", async () => {
      const db = await authedDb(HOST);
      await assertFails(
        updateDoc(doc(db, "games", IN_PROGRESS), {
          state: "finished",
          winning_team: "traitor",
        })
      );
    });

    it("stops an outsider from seizing host_id on somebody else's lobby", async () => {
      const db = await authedDb(OUTSIDER);
      await assertFails(
        updateDoc(doc(db, "games", WAITING), { host_id: OUTSIDER })
      );
    });
  });

  // ─── update: joining ─────────────────────────────────────────────
  describe("update (joining)", () => {
    it("lets a user join a waiting lobby by appending themselves to player_ids", async () => {
      const db = await authedDb(OUTSIDER);
      await assertSucceeds(
        updateDoc(doc(db, "games", WAITING), {
          player_ids: [HOST, PLAYER, OUTSIDER],
          last_activity_at: new Date(),
        })
      );
    });

    it("stops a user from adding somebody other than themselves", async () => {
      const db = await authedDb(OUTSIDER);
      await assertFails(
        updateDoc(doc(db, "games", WAITING), {
          player_ids: [HOST, PLAYER, "user_bystander"],
        })
      );
    });

    it("stops a user from piggybacking other field changes onto a join", async () => {
      const db = await authedDb(OUTSIDER);
      await assertFails(
        updateDoc(doc(db, "games", WAITING), {
          player_ids: [HOST, PLAYER, OUTSIDER],
          max_players: 99,
        })
      );
    });

    // SKIP: currently vulnerable — see finding #2. Un-skip when firestore.rules is fixed.
    it.skip("stops a non-participant from injecting themselves into an in_progress game", async () => {
      const db = await authedDb(OUTSIDER);
      await assertFails(
        updateDoc(doc(db, "games", IN_PROGRESS), {
          player_ids: [HOST, PLAYER, THIRD, OUTSIDER],
          last_activity_at: new Date(),
        })
      );
    });

    // SKIP: currently vulnerable — see finding #2. Un-skip when firestore.rules is fixed.
    it.skip("stops a user from joining a lobby that is already at max_players", async () => {
      const db = await authedDb(OUTSIDER);
      await assertFails(
        updateDoc(doc(db, "games", FULL), {
          player_ids: [HOST, PLAYER, THIRD, "user_fourth", OUTSIDER],
          last_activity_at: new Date(),
        })
      );
    });

    // SKIP: currently vulnerable — see finding #3. Un-skip when firestore.rules is fixed.
    it.skip("stops player_ids from being overwritten in a way that evicts existing members", async () => {
      // An existing member cannot kick everyone else out...
      const player = await authedDb(PLAYER);
      await assertFails(
        updateDoc(doc(player, "games", WAITING), { player_ids: [PLAYER] })
      );

      // ...and neither can a complete outsider.
      const outsider = await authedDb(OUTSIDER);
      await assertFails(
        updateDoc(doc(outsider, "games", WAITING), { player_ids: [OUTSIDER] })
      );
    });
  });

  // ─── delete ──────────────────────────────────────────────────────
  describe("delete", () => {
    it("lets the host disband their own lobby", async () => {
      const db = await authedDb(HOST);
      await assertSucceeds(deleteDoc(doc(db, "games", WAITING)));
    });

    it("stops a non-host player from deleting the lobby", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(deleteDoc(doc(db, "games", WAITING)));
    });

    it("stops an outsider from deleting the lobby", async () => {
      const db = await authedDb(OUTSIDER);
      await assertFails(deleteDoc(doc(db, "games", WAITING)));
    });

    it("stops a signed-out client from deleting the lobby", async () => {
      const db = await anonDb();
      await assertFails(deleteDoc(doc(db, "games", WAITING)));
    });
  });
});
