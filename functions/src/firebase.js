// Firebase Admin bootstrap: the ONE initializeApp() call in the deployed
// functions (scripts/ holds standalone CLI tools with their own).
//
// Every module that needs Firestore, Auth or Messaging takes it from here, so
// the Admin SDK is initialised exactly once, on first require, before any
// handler can run. The pure modules (config, validation, rules, cards) must
// never require this file: unit tests load them with no credentials.

const { initializeApp, getApps } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

// scripts/delete-account.js initializes the default app itself, with the
// project id it has printed, before it loads the deletion code that requires
// this module; initializing it again here would throw. Nothing else does, so
// in the deployed functions it doesn't exist yet at this point.
if (!getApps().some((app) => app.name === "[DEFAULT]")) initializeApp();
const db = getFirestore();

module.exports = {
  db,
  FieldValue,
  getAuth,
  getMessaging,
};
