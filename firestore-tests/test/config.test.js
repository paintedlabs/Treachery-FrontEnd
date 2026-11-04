/**
 * Rules under test: match /config/{doc}
 *
 * config/ios holds the iOS minimum-build gate. The app reads it at launch,
 * before anyone signs in, so it must be readable without auth. Only the
 * Firebase console (Admin SDK, which bypasses rules) may change it: a client
 * that could write it could lock every iOS user out.
 */

"use strict";

const { doc, getDoc, setDoc, updateDoc, deleteDoc } = require("firebase/firestore");
const { seed, authedDb, anonDb, assertSucceeds, assertFails } = require("./helpers");

const ALICE = "user_alice";

function iosConfigDoc(overrides = {}) {
  return {
    min_build: 42,
    message: "Update to keep playing.",
    store_url: "https://apps.apple.com/app/id0000000000",
    ...overrides,
  };
}

describe("config/{doc}", () => {
  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, "config", "ios"), iosConfigDoc());
    });
  });

  describe("read", () => {
    it("lets a signed-out client read config/ios (the gate runs before sign-in)", async () => {
      const db = await anonDb();
      await assertSucceeds(getDoc(doc(db, "config", "ios")));
    });

    it("lets a signed-in user read config/ios", async () => {
      const db = await authedDb(ALICE);
      await assertSucceeds(getDoc(doc(db, "config", "ios")));
    });
  });

  describe("write", () => {
    it("stops a signed-in user from changing min_build", async () => {
      const db = await authedDb(ALICE);
      await assertFails(updateDoc(doc(db, "config", "ios"), { min_build: 9999 }));
    });

    it("stops a signed-in user from creating a config doc", async () => {
      const db = await authedDb(ALICE);
      await assertFails(setDoc(doc(db, "config", "android"), iosConfigDoc()));
    });

    it("stops a signed-in user from deleting config/ios", async () => {
      const db = await authedDb(ALICE);
      await assertFails(deleteDoc(doc(db, "config", "ios")));
    });

    it("stops a signed-out client from overwriting config/ios", async () => {
      const db = await anonDb();
      await assertFails(setDoc(doc(db, "config", "ios"), iosConfigDoc({ min_build: 9999 })));
    });
  });
});
