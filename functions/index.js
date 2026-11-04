// Cloud Functions entry point (package.json "main").
//
// DEPLOY CONTRACT: Firebase identifies every deployed function by its export
// NAME on this module. Renaming, adding or removing a name below makes
// `firebase deploy` delete a function and create a new one (a new Cloud Run
// service with fresh IAM bindings). Every export is listed explicitly, so a
// helper exported from a src/ module can never become a function by accident.
// Implementations live under src/; this file only wires names to them.

const users = require("./src/callables/users");
const account = require("./src/callables/account");
const lobby = require("./src/callables/lobby");
const gameplay = require("./src/callables/gameplay");
const turns = require("./src/callables/turns");
const abilities = require("./src/callables/abilities");
const planechase = require("./src/callables/planechase");
const triggers = require("./src/triggers");

exports.registerFcmToken = users.registerFcmToken;
exports.acceptFriendRequest = users.acceptFriendRequest;
exports.removeFriend = users.removeFriend;

exports.deleteAccount = account.deleteAccount;

exports.createGame = lobby.createGame;
exports.startGame = lobby.startGame;
exports.joinGame = lobby.joinGame;
exports.leaveGame = lobby.leaveGame;
exports.updateGameSettings = lobby.updateGameSettings;

exports.adjustLife = gameplay.adjustLife;
exports.eliminatePlayer = gameplay.eliminatePlayer;
exports.unveilPlayer = gameplay.unveilPlayer;
exports.endGame = gameplay.endGame;

exports.setActivePlayer = turns.setActivePlayer;
exports.advanceTurn = turns.advanceTurn;
exports.reorderSeats = turns.reorderSeats;

exports.resolveMetamorph = abilities.resolveMetamorph;
exports.resolvePuppetMaster = abilities.resolvePuppetMaster;
exports.resolveWearerOfMasks = abilities.resolveWearerOfMasks;

exports.rollPlanarDie = planechase.rollPlanarDie;
exports.resolvePhenomenon = planechase.resolvePhenomenon;
exports.selectPlane = planechase.selectPlane;

exports.cleanupStaleGames = triggers.cleanupStaleGames;
exports.onPlayerJoined = triggers.onPlayerJoined;
exports.onGameFinished = triggers.onGameFinished;
