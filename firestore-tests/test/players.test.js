/**
 * Rules under test: match /games/{gameId}/players/{playerId}
 * (firestore.rules ~lines 72-110) plus onlyUnveilChanged() /
 * onlyPlayerColorChanged() / onlyCommanderNameChanged() / isGameHost().
 *
 * The player doc is where the game's secrets live: `role` and
 * `identity_card_id` are what the whole hidden-role format hangs on.
 */

"use strict";

const { doc, getDoc, setDoc, updateDoc, deleteDoc } = require("firebase/firestore");
const {
  seed,
  authedDb,
  anonDb,
  gameDoc,
  playerDoc,
  assertSucceeds,
  assertFails,
} = require("./helpers");

const HOST = "user_host";
const PLAYER = "user_player";
const THIRD = "user_third";
const JOINER = "user_joiner";
const OUTSIDER = "user_outsider";

const WAITING = "game_waiting";
const IN_PROGRESS = "game_in_progress";

const P_HOST = "p_host";
const P_PLAYER = "p_player";
const P_THIRD = "p_third";

const waitingPlayer = (gameId, playerId) => ["games", gameId, "players", playerId];

describe("games/{gameId}/players/{playerId}", () => {
  beforeEach(async () => {
    await seed(async (db) => {
      // A lobby that JOINER has already been admitted to (player_ids updated),
      // but where they have not yet written their player doc.
      await setDoc(
        doc(db, "games", WAITING),
        gameDoc(HOST, { player_ids: [HOST, PLAYER, JOINER] })
      );
      await setDoc(
        doc(db, ...waitingPlayer(WAITING, P_HOST)),
        playerDoc(HOST, { order_id: 0 })
      );
      await setDoc(
        doc(db, ...waitingPlayer(WAITING, P_PLAYER)),
        playerDoc(PLAYER, { order_id: 1 })
      );

      // A live game where roles have been dealt by the Cloud Function.
      await setDoc(
        doc(db, "games", IN_PROGRESS),
        gameDoc(HOST, {
          state: "in_progress",
          player_ids: [HOST, PLAYER, THIRD],
          join_code: "WXYZ",
        })
      );
      await setDoc(
        doc(db, ...waitingPlayer(IN_PROGRESS, P_HOST)),
        playerDoc(HOST, { order_id: 0, role: "leader", identity_card_id: "card-leader-1" })
      );
      await setDoc(
        doc(db, ...waitingPlayer(IN_PROGRESS, P_PLAYER)),
        playerDoc(PLAYER, { order_id: 1, role: "traitor", identity_card_id: "card-traitor-1" })
      );
      await setDoc(
        doc(db, ...waitingPlayer(IN_PROGRESS, P_THIRD)),
        playerDoc(THIRD, { order_id: 2, role: "assassin", identity_card_id: "card-assassin-1" })
      );
    });
  });

  // ─── read ────────────────────────────────────────────────────────
  describe("read", () => {
    it("lets a participant read the other players in their game", async () => {
      const db = await authedDb(PLAYER);
      await assertSucceeds(getDoc(doc(db, ...waitingPlayer(IN_PROGRESS, P_HOST))));
    });

    it("hides player docs from a non-participant", async () => {
      const db = await authedDb(OUTSIDER);
      await assertFails(getDoc(doc(db, ...waitingPlayer(IN_PROGRESS, P_PLAYER))));
    });

    it("hides player docs from a signed-out client", async () => {
      const db = await anonDb();
      await assertFails(getDoc(doc(db, ...waitingPlayer(IN_PROGRESS, P_PLAYER))));
    });
    it("keeps secret roles hidden from an outsider who tries the player_ids injection", async () => {
      const db = await authedDb(OUTSIDER);

      // Attempt the finding-#2 injection. Once the join rule is fixed this write
      // is denied outright; today it lands. Either way the read below must fail
      // — an outsider must never see another player's role / identity_card_id.
      await updateDoc(doc(db, "games", IN_PROGRESS), {
        player_ids: [HOST, PLAYER, THIRD, OUTSIDER],
        last_activity_at: new Date(),
      }).catch(() => {});

      await assertFails(getDoc(doc(db, ...waitingPlayer(IN_PROGRESS, P_PLAYER))));
      await assertFails(getDoc(doc(db, ...waitingPlayer(IN_PROGRESS, P_HOST))));
    });
  });

  // ─── create ──────────────────────────────────────────────────────
  describe("create", () => {
    it("lets an admitted player create their own player doc with no role or card", async () => {
      const db = await authedDb(JOINER);
      await assertSucceeds(
        setDoc(
          doc(db, ...waitingPlayer(WAITING, "p_joiner")),
          playerDoc(JOINER, { order_id: 2 })
        )
      );
    });

    it("accepts a player doc that omits role / identity_card_id entirely (Swift Codable skips nils)", async () => {
      const db = await authedDb(JOINER);
      await assertSucceeds(
        setDoc(doc(db, ...waitingPlayer(WAITING, "p_joiner_slim")), {
          user_id: JOINER,
          display_name: "Joiner",
          life_total: 40,
          order_id: 2,
          is_unveiled: false,
          is_eliminated: false,
        })
      );
    });

    it("stops a user from creating a player doc for somebody else", async () => {
      const db = await authedDb(JOINER);
      await assertFails(
        setDoc(
          doc(db, ...waitingPlayer(WAITING, "p_impostor")),
          playerDoc(OUTSIDER, { order_id: 2 })
        )
      );
    });

    it("stops a player from dealing themselves a role", async () => {
      const db = await authedDb(JOINER);
      await assertFails(
        setDoc(
          doc(db, ...waitingPlayer(WAITING, "p_joiner")),
          playerDoc(JOINER, { role: "traitor" })
        )
      );
    });

    it("stops a player from picking their own identity card", async () => {
      const db = await authedDb(JOINER);
      await assertFails(
        setDoc(
          doc(db, ...waitingPlayer(WAITING, "p_joiner")),
          playerDoc(JOINER, { identity_card_id: "card-traitor-1" })
        )
      );
    });

    it("stops a player from pre-unveiling themselves on create", async () => {
      const db = await authedDb(JOINER);
      await assertFails(
        setDoc(
          doc(db, ...waitingPlayer(WAITING, "p_joiner")),
          playerDoc(JOINER, { order_id: 2, is_unveiled: true })
        )
      );
    });

    it("stops a player from entering pre-eliminated on create", async () => {
      const db = await authedDb(JOINER);
      await assertFails(
        setDoc(
          doc(db, ...waitingPlayer(WAITING, "p_joiner")),
          playerDoc(JOINER, { order_id: 2, is_eliminated: true })
        )
      );
    });

    it("stops a signed-out client from creating a player doc", async () => {
      const db = await anonDb();
      await assertFails(
        setDoc(doc(db, ...waitingPlayer(WAITING, "p_anon")), playerDoc(JOINER))
      );
    });

    it("stops a non-member from creating a player doc in somebody else's in_progress game", async () => {
      const db = await authedDb(OUTSIDER);
      await assertFails(
        setDoc(
          doc(db, ...waitingPlayer(IN_PROGRESS, "p_gatecrasher")),
          playerDoc(OUTSIDER, {
            display_name: "GATECRASHER",
            life_total: 9999,
            order_id: -1,
          })
        )
      );
    });
  });

  // ─── update ──────────────────────────────────────────────────────
  describe("update (unveil)", () => {
    it("lets a player unveil themselves", async () => {
      const db = await authedDb(PLAYER);
      await assertSucceeds(
        updateDoc(doc(db, ...waitingPlayer(IN_PROGRESS, P_PLAYER)), {
          is_unveiled: true,
        })
      );
    });

    it("stops a player from re-hiding themselves after unveiling", async () => {
      await seed(async (db) => {
        await setDoc(
          doc(db, ...waitingPlayer(IN_PROGRESS, P_PLAYER)),
          playerDoc(PLAYER, {
            order_id: 1,
            role: "traitor",
            identity_card_id: "card-traitor-1",
            is_unveiled: true,
          })
        );
      });

      const db = await authedDb(PLAYER);
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(IN_PROGRESS, P_PLAYER)), {
          is_unveiled: false,
        })
      );
    });

    it("stops a player from unveiling somebody else", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(IN_PROGRESS, P_HOST)), {
          is_unveiled: true,
        })
      );
    });

    it("stops the host from unveiling another player", async () => {
      const db = await authedDb(HOST);
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(IN_PROGRESS, P_PLAYER)), {
          is_unveiled: true,
        })
      );
    });

    it("stops life_total being smuggled in alongside an unveil", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(IN_PROGRESS, P_PLAYER)), {
          is_unveiled: true,
          life_total: 100,
        })
      );
    });
  });

  describe("update (cosmetics)", () => {
    it("lets a player set their own player_color", async () => {
      const db = await authedDb(PLAYER);
      await assertSucceeds(
        updateDoc(doc(db, ...waitingPlayer(WAITING, P_PLAYER)), {
          player_color: "#ff0055",
        })
      );
    });

    it("lets a player set their own commander_name", async () => {
      const db = await authedDb(PLAYER);
      await assertSucceeds(
        updateDoc(doc(db, ...waitingPlayer(WAITING, P_PLAYER)), {
          commander_name: "Edgar Markov",
        })
      );
    });

    it("rejects a player_color write that also changes life_total", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(WAITING, P_PLAYER)), {
          player_color: "#ff0055",
          life_total: 999,
        })
      );
    });

    it("rejects a commander_name write that also changes role", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(WAITING, P_PLAYER)), {
          commander_name: "Edgar Markov",
          role: "leader",
        })
      );
    });

    it("stops a player from recolouring somebody else", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(WAITING, P_HOST)), {
          player_color: "#000000",
        })
      );
    });

    it("stops a non-participant from recolouring a player", async () => {
      const db = await authedDb(OUTSIDER);
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(WAITING, P_PLAYER)), {
          player_color: "#000000",
        })
      );
    });

    // ── in-game rename (onlyDisplayNameChanged) ──────────────────

    it("lets a player rename themselves", async () => {
      const db = await authedDb(PLAYER);
      await assertSucceeds(
        updateDoc(doc(db, ...waitingPlayer(WAITING, P_PLAYER)), {
          display_name: "Krenko, Mob Boss",
        })
      );
    });

    it("stops a player from renaming somebody else", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(WAITING, P_HOST)), {
          display_name: "Not Your Name",
        })
      );
    });

    it("rejects a rename that also changes life_total", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(WAITING, P_PLAYER)), {
          display_name: "Sneaky",
          life_total: 999,
        })
      );
    });

    it("rejects an empty display_name", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(WAITING, P_PLAYER)), {
          display_name: "",
        })
      );
    });

    it("rejects a display_name over 40 characters", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(WAITING, P_PLAYER)), {
          display_name: "X".repeat(41),
        })
      );
    });

    it("rejects a non-string display_name", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(WAITING, P_PLAYER)), {
          display_name: 42,
        })
      );
    });
  });

  describe("update (game state stays server-side)", () => {
    it("stops a player from editing their own life_total", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(IN_PROGRESS, P_PLAYER)), {
          life_total: 100,
        })
      );
    });

    it("stops a player from editing somebody else's life_total", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(IN_PROGRESS, P_HOST)), { life_total: 0 })
      );
    });

    it("stops a player from changing their own elimination flag", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(IN_PROGRESS, P_PLAYER)), {
          is_eliminated: true,
        })
      );
    });

    it("stops a player from rerolling their own role", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(IN_PROGRESS, P_PLAYER)), {
          role: "leader",
        })
      );
    });

    it("stops a player from swapping their own identity_card_id", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(IN_PROGRESS, P_PLAYER)), {
          identity_card_id: "card-leader-1",
        })
      );
    });

    it("stops a signed-out client from updating a player doc", async () => {
      const db = await anonDb();
      await assertFails(
        updateDoc(doc(db, ...waitingPlayer(WAITING, P_PLAYER)), {
          player_color: "#000000",
        })
      );
    });
  });

  // ─── delete ──────────────────────────────────────────────────────
  describe("delete", () => {
    it("lets a player leave by deleting their own player doc", async () => {
      const db = await authedDb(PLAYER);
      await assertSucceeds(
        deleteDoc(doc(db, ...waitingPlayer(WAITING, P_PLAYER)))
      );
    });

    it("lets the host kick any player in their own lobby", async () => {
      const db = await authedDb(HOST);
      await assertSucceeds(
        deleteDoc(doc(db, ...waitingPlayer(WAITING, P_PLAYER)))
      );
    });

    it("stops a player from kicking another player", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(deleteDoc(doc(db, ...waitingPlayer(WAITING, P_HOST))));
    });

    it("stops a non-participant from deleting a player doc", async () => {
      const db = await authedDb(OUTSIDER);
      await assertFails(deleteDoc(doc(db, ...waitingPlayer(WAITING, P_PLAYER))));
    });

    it("stops a signed-out client from deleting a player doc", async () => {
      const db = await anonDb();
      await assertFails(deleteDoc(doc(db, ...waitingPlayer(WAITING, P_PLAYER))));
    });

    it("stops a player from deleting their own doc mid-game", async () => {
      const db = await authedDb(PLAYER);
      await assertFails(
        deleteDoc(doc(db, ...waitingPlayer(IN_PROGRESS, P_PLAYER)))
      );
    });

    it("stops the host from kicking a player mid-game", async () => {
      const db = await authedDb(HOST);
      await assertFails(
        deleteDoc(doc(db, ...waitingPlayer(IN_PROGRESS, P_PLAYER)))
      );
    });
  });
});
