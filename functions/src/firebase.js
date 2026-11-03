// Firebase Admin bootstrap: the ONE initializeApp() call in the deployed
// functions (scripts/ holds standalone CLI tools with their own).
//
// Every module that needs Firestore or Messaging takes it from here, so the
// Admin SDK is initialised exactly once, on first require, before any
// handler can run. The pure modules (config, validation, rules, cards) must
// never require this file: unit tests load them with no credentials.

const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

module.exports = {
  db,
  FieldValue,
  getMessaging,
};
