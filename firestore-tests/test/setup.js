/**
 * Mocha root hooks: one shared RulesTestEnvironment for the whole run,
 * wiped between tests so each spec starts from a known fixture state.
 */

"use strict";

const { setLogLevel } = require("firebase/firestore");
const { getTestEnv, cleanupTestEnv, clearData } = require("./helpers");

// Every assertFails() case makes the SDK log a PERMISSION_DENIED gRPC error.
// Those are the expected result here, and they drown out the mocha reporter.
// Set FIRESTORE_DEBUG=1 to get them back while debugging a rule.
setLogLevel(process.env.FIRESTORE_DEBUG ? "debug" : "silent");

exports.mochaHooks = {
  async beforeAll() {
    this.timeout(60000);
    await getTestEnv();
  },
  async afterEach() {
    await clearData();
  },
  async afterAll() {
    await cleanupTestEnv();
  },
};
