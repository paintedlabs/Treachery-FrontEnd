/**
 * Rules under test: match /friend_requests/{requestId}  (firestore.rules ~lines 25-38)
 */

"use strict";

const { doc, getDoc, setDoc, updateDoc, deleteDoc } = require("firebase/firestore");
const {
  seed,
  authedDb,
  anonDb,
  friendRequestDoc,
  assertSucceeds,
  assertFails,
} = require("./helpers");

const ALICE = "user_alice";
const BOB = "user_bob";
const MALLORY = "user_mallory";
const REQ = "req_alice_to_bob";

describe("friend_requests/{requestId}", () => {
  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, "friend_requests", REQ), friendRequestDoc(ALICE, BOB));
    });
  });

  describe("read", () => {
    it("lets the sender read their own outgoing request", async () => {
      const db = await authedDb(ALICE);
      await assertSucceeds(getDoc(doc(db, "friend_requests", REQ)));
    });

    it("lets the recipient read an incoming request", async () => {
      const db = await authedDb(BOB);
      await assertSucceeds(getDoc(doc(db, "friend_requests", REQ)));
    });

    it("hides a request from an unrelated user", async () => {
      const db = await authedDb(MALLORY);
      await assertFails(getDoc(doc(db, "friend_requests", REQ)));
    });

    it("hides a request from a signed-out client", async () => {
      const db = await anonDb();
      await assertFails(getDoc(doc(db, "friend_requests", REQ)));
    });
  });

  describe("create", () => {
    it("lets a user send a pending request from their own uid", async () => {
      const db = await authedDb(ALICE);
      await assertSucceeds(
        setDoc(doc(db, "friend_requests", "req_new"), friendRequestDoc(ALICE, MALLORY))
      );
    });

    it("stops a user from forging a request from someone else's uid", async () => {
      const db = await authedDb(MALLORY);
      await assertFails(
        setDoc(doc(db, "friend_requests", "req_forged"), friendRequestDoc(ALICE, BOB))
      );
    });

    it("stops a user from creating a pre-accepted request", async () => {
      const db = await authedDb(ALICE);
      await assertFails(
        setDoc(
          doc(db, "friend_requests", "req_preaccepted"),
          friendRequestDoc(ALICE, BOB, { status: "accepted" })
        )
      );
    });

    it("stops a signed-out client from creating a request", async () => {
      const db = await anonDb();
      await assertFails(
        setDoc(doc(db, "friend_requests", "req_anon"), friendRequestDoc(ALICE, BOB))
      );
    });
  });

  describe("update", () => {
    it("lets the recipient accept a request", async () => {
      const db = await authedDb(BOB);
      await assertSucceeds(
        updateDoc(doc(db, "friend_requests", REQ), { status: "accepted" })
      );
    });

    it("stops the sender from accepting their own request", async () => {
      const db = await authedDb(ALICE);
      await assertFails(
        updateDoc(doc(db, "friend_requests", REQ), { status: "accepted" })
      );
    });

    it("stops an unrelated user from touching the request", async () => {
      const db = await authedDb(MALLORY);
      await assertFails(
        updateDoc(doc(db, "friend_requests", REQ), { status: "accepted" })
      );
    });

    it("stops the recipient from rewriting from_user_id", async () => {
      const db = await authedDb(BOB);
      await assertFails(
        updateDoc(doc(db, "friend_requests", REQ), {
          status: "accepted",
          from_user_id: MALLORY,
        })
      );
    });

    it("stops the recipient from rewriting to_user_id", async () => {
      const db = await authedDb(BOB);
      await assertFails(
        updateDoc(doc(db, "friend_requests", REQ), {
          status: "declined",
          to_user_id: MALLORY,
        })
      );
    });
  });

  describe("delete", () => {
    it("denies deletion to the recipient", async () => {
      const db = await authedDb(BOB);
      await assertFails(deleteDoc(doc(db, "friend_requests", REQ)));
    });

    it("denies deletion to the sender", async () => {
      const db = await authedDb(ALICE);
      await assertFails(deleteDoc(doc(db, "friend_requests", REQ)));
    });
  });
});
