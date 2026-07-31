/**
 * Rules under test: match /users/{userId}  (firestore.rules ~lines 9-20)
 * plus the onlyFriendIdsChanged() / onlyFcmTokenChanged() helpers.
 */

"use strict";

const { doc, getDoc, setDoc, updateDoc, deleteDoc } = require("firebase/firestore");
const {
  seed,
  authedDb,
  anonDb,
  userDoc,
  assertSucceeds,
  assertFails,
} = require("./helpers");

const ALICE = "user_alice";
const BOB = "user_bob";
const MALLORY = "user_mallory";
const CAROL = "user_carol";
const DAVE = "user_dave";

describe("users/{userId}", () => {
  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, "users", ALICE), userDoc(ALICE));
      await setDoc(doc(db, "users", BOB), userDoc(BOB, { friend_ids: [CAROL] }));
      await setDoc(doc(db, "users", MALLORY), userDoc(MALLORY));
    });
  });

  // ─── read ────────────────────────────────────────────────────────
  describe("read", () => {
    it("lets a user read their own profile", async () => {
      const db = await authedDb(ALICE);
      await assertSucceeds(getDoc(doc(db, "users", ALICE)));
    });

    it("denies a signed-out client any user profile", async () => {
      const db = await anonDb();
      await assertFails(getDoc(doc(db, "users", ALICE)));
    });

    // SKIP: currently vulnerable — see finding #1. Un-skip when firestore.rules is fixed.
    it.skip("denies a signed-in user access to another user's PII (email / phone_number / fcm_token)", async () => {
      const mallory = await authedDb(MALLORY);
      await assertFails(getDoc(doc(mallory, "users", BOB)));

      // The same hole is open to an anonymous guest account, which needs no
      // real identity at all.
      const guest = await authedDb("anon_guest_9f2c");
      await assertFails(getDoc(doc(guest, "users", BOB)));
    });
  });

  // ─── create ──────────────────────────────────────────────────────
  describe("create", () => {
    it("lets a user create their own profile document", async () => {
      const db = await authedDb(DAVE);
      await assertSucceeds(setDoc(doc(db, "users", DAVE), userDoc(DAVE)));
    });

    it("stops a user from creating a profile under someone else's uid", async () => {
      const db = await authedDb(DAVE);
      await assertFails(setDoc(doc(db, "users", "user_erin"), userDoc("user_erin")));
    });

    it("stops a signed-out client from creating a profile", async () => {
      const db = await anonDb();
      await assertFails(setDoc(doc(db, "users", DAVE), userDoc(DAVE)));
    });
  });

  // ─── update ──────────────────────────────────────────────────────
  describe("update", () => {
    it("lets a user update their own profile fields", async () => {
      const db = await authedDb(ALICE);
      await assertSucceeds(
        updateDoc(doc(db, "users", ALICE), { display_name: "Alice the Brave" })
      );
    });

    it("lets a user rotate their own fcm_token", async () => {
      const db = await authedDb(ALICE);
      await assertSucceeds(
        updateDoc(doc(db, "users", ALICE), { fcm_token: "fcm-token-rotated" })
      );
    });

    it("lets a user edit their own friend_ids", async () => {
      const db = await authedDb(BOB);
      await assertSucceeds(
        updateDoc(doc(db, "users", BOB), { friend_ids: [CAROL, ALICE] })
      );
    });

    it("stops a user from editing another user's display_name", async () => {
      const db = await authedDb(MALLORY);
      await assertFails(
        updateDoc(doc(db, "users", BOB), { display_name: "pwned" })
      );
    });

    it("stops a user from writing another user's fcm_token (push-notification hijack)", async () => {
      const db = await authedDb(MALLORY);
      await assertFails(
        updateDoc(doc(db, "users", BOB), { fcm_token: "attacker-device" })
      );
    });

    it("stops a user from rewriting another user's friend_ids to a list that excludes them", async () => {
      // The one guard onlyFriendIdsChanged() does apply: the caller must end up
      // inside the new array. This locks that guard in place.
      const db = await authedDb(MALLORY);
      await assertFails(
        updateDoc(doc(db, "users", BOB), { friend_ids: ["user_someone_else"] })
      );
    });

    it("stops a user from smuggling extra fields alongside a friend_ids write", async () => {
      const db = await authedDb(MALLORY);
      await assertFails(
        updateDoc(doc(db, "users", BOB), {
          friend_ids: [CAROL, MALLORY],
          elo_rating: 9999,
        })
      );
    });

    it("stops a signed-out client from updating a profile", async () => {
      const db = await anonDb();
      await assertFails(updateDoc(doc(db, "users", ALICE), { display_name: "x" }));
    });

    // SKIP: residual gap after the friend_ids hardening — the wipe is now
    // blocked, but a one-sided friendship can still be forced. Rules cannot
    // verify an accepted friend_request (random doc ids, so no deterministic
    // get() path), so closing this means moving accept/remove into a callable
    // and denying cross-user writes entirely. Un-skip then.
    it.skip("stops a user from forcing themselves into another user's friend_ids", async () => {
      const mallory = await authedDb(MALLORY);
      await assertFails(
        updateDoc(doc(mallory, "users", BOB), { friend_ids: [CAROL, MALLORY] })
      );
    });
    it("stops a user from overwriting another user's friend_ids and wiping their real friends", async () => {
      const mallory = await authedDb(MALLORY);
      await assertFails(
        updateDoc(doc(mallory, "users", BOB), { friend_ids: [MALLORY] })
      );
    });
  });

  // ─── delete ──────────────────────────────────────────────────────
  describe("delete", () => {
    it("denies deletion even to the profile's owner", async () => {
      const db = await authedDb(ALICE);
      await assertFails(deleteDoc(doc(db, "users", ALICE)));
    });

    it("denies deletion to another user", async () => {
      const db = await authedDb(MALLORY);
      await assertFails(deleteDoc(doc(db, "users", BOB)));
    });
  });
});
