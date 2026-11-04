// Non-callable functions: the hourly stale-game sweep and the Firestore
// triggers.

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { db, FieldValue } = require("./firebase");
const { sanitizeCommanderKey } = require("./validation");
const { isTreacheryMode } = require("./rules");
const { notifyPlayers } = require("./notifications");

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: cleanupStaleGames (Scheduled)
// Runs every hour. Deletes games stuck in "waiting" or
// "in_progress" with no activity for 24 hours.
// ════════════════════════════════════════════════════════════════

/**
 * Up to `limit` games in `state` whose `field` is older than `cutoff`,
 * oldest first.
 *
 * Equality on state plus a range on `field` is served only by the composite
 * index (state ASC, field ASC) in firestore.indexes.json. Without it the
 * query fails with FAILED_PRECONDITION; the emulator never enforces indexes,
 * so test/game-logic.test.js checks the declarations. The error is rethrown
 * naming the query, so the log says which one failed.
 */
async function findGamesOlderThan(state, field, cutoff, limit) {
  try {
    const snap = await db
      .collection("games")
      .where("state", "==", state)
      .where(field, "<", cutoff)
      .limit(limit)
      .get();
    return snap.docs;
  } catch (error) {
    throw new Error(
      `query games where state == "${state}" and ${field} < ${cutoff.toISOString()} failed: ${error.message}`,
      { cause: error }
    );
  }
}

/**
 * One pass of the sweep: deletes every game stuck in "waiting" or
 * "in_progress" with no activity in the 24 hours before `now`, with its
 * players subcollection. Each query reads at most `limit` games, so a large
 * backlog drains over several runs.
 *
 * A failure while sweeping one state is logged and skips that state for
 * this run only; the other state still runs. Returns { deleted, failedStates }.
 *
 * Exported for the emulator integration test, which runs it with a fixed
 * clock. index.js does not export it, so it is never deployed as a function.
 */
async function sweepStaleGames({ now = new Date(), limit = 100 } = {}) {
  const cutoff = new Date(now.getTime() - 24 * 60 * 60 * 1000);

  // Find stale games: last_activity_at (or created_at as fallback) older than 24h
  // We query "waiting" and "in_progress" separately since Firestore
  // doesn't support != on state and inequality on timestamp in one query.

  const staleStates = ["waiting", "in_progress"];
  let deleted = 0;
  const failedStates = [];

  for (const state of staleStates) {
    try {
      // First try games with last_activity_at
      const withActivity = await findGamesOlderThan(state, "last_activity_at", cutoff, limit);

      // Also find games without last_activity_at (legacy) using created_at
      const withoutActivity = await findGamesOlderThan(state, "created_at", cutoff, limit);

      // Merge, deduplicate
      const gameIds = new Set();
      const gameDocs = [];

      for (const doc of [...withActivity, ...withoutActivity]) {
        if (gameIds.has(doc.id)) continue;
        // Double-check: if it has last_activity_at and it's recent, skip
        const data = doc.data();
        if (data.last_activity_at && data.last_activity_at.toDate() >= cutoff) continue;
        gameIds.add(doc.id);
        gameDocs.push(doc);
      }

      // Delete each stale game and its players subcollection
      for (const gameDoc of gameDocs) {
        const playersSnap = await db
          .collection(`games/${gameDoc.id}/players`)
          .get();

        const batch = db.batch();
        playersSnap.docs.forEach((pDoc) => batch.delete(pDoc.ref));
        batch.delete(gameDoc.ref);
        await batch.commit();
        deleted++;
      }
    } catch (error) {
      // Typically FAILED_PRECONDITION while an index is missing or still
      // building.
      failedStates.push(state);
      console.error(`cleanupStaleGames: skipped "${state}" games this run:`, error);
    }
  }

  return { deleted, failedStates };
}

exports.sweepStaleGames = sweepStaleGames;

exports.cleanupStaleGames = onSchedule("every 1 hours", async () => {
  const { deleted, failedStates } = await sweepStaleGames();
  console.log(`cleanupStaleGames: deleted ${deleted} stale games.`);

  // A failure still fails the run, as it always has, so it shows up as a
  // failed invocation and not only as a log line.
  if (failedStates.length > 0) {
    throw new Error(
      `cleanupStaleGames: could not sweep ${failedStates.join(", ")} games; see the errors above.`
    );
  }
});

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: onPlayerJoined (Firestore trigger)
// Sends a push notification when a new player joins a lobby.
// ════════════════════════════════════════════════════════════════

exports.onPlayerJoined = onDocumentCreated(
  "games/{gameId}/players/{playerId}",
  async (event) => {
    const player = event.data?.data();
    if (!player) return;

    const gameId = event.params.gameId;
    const displayName = player.display_name || "Someone";

    // Update last_activity_at on the game
    await db.doc(`games/${gameId}`).update({
      last_activity_at: FieldValue.serverTimestamp(),
    });

    // Notify other players
    await notifyPlayers(
      gameId,
      player.user_id,
      "Player Joined",
      `${displayName} joined the game!`
    );
  }
);

// ════════════════════════════════════════════════════════════════
// FIRESTORE TRIGGER: onGameFinished
// Fires when a game's state transitions to "finished".
// Updates ELO ratings for all players (and per-deck stats).
// ════════════════════════════════════════════════════════════════

exports.onGameFinished = onDocumentUpdated("games/{gameId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  // Only fire on state transition to finished
  if (before.state === "finished" || after.state !== "finished") return;

  const gameId = event.params.gameId;
  const game = after;

  // Fetch all players
  const playersSnap = await db.collection(`games/${gameId}/players`).get();
  const players = playersSnap.docs.map((d) => ({ id: d.id, ...d.data() }));

  if (players.length < 2) return; // Need at least 2 players for ELO

  // Determine winners and losers
  let winnerUserIds = [];
  let loserUserIds = [];

  if (isTreacheryMode(game.game_mode)) {
    // Treachery: use winning_team
    const winningTeam = game.winning_team;
    if (!winningTeam) return;

    for (const player of players) {
      if (!player.role) continue;
      const isWinner =
        (winningTeam === "leader" && (player.role === "leader" || player.role === "guardian")) ||
        (winningTeam === "assassin" && player.role === "assassin") ||
        (winningTeam === "traitor" && player.role === "traitor");
      if (isWinner) {
        winnerUserIds.push(player.user_id);
      } else {
        loserUserIds.push(player.user_id);
      }
    }
  } else {
    // Non-treachery: use winner_user_ids from game doc
    winnerUserIds = game.winner_user_ids || [];
    if (winnerUserIds.length === 0) return; // No winners declared, skip ELO

    loserUserIds = players
      .map((p) => p.user_id)
      .filter((uid) => !winnerUserIds.includes(uid));
  }

  if (winnerUserIds.length === 0 || loserUserIds.length === 0) return;

  // Build a map of userId -> sanitized commanderName for deck stats
  const playerCommanders = {};
  for (const p of players) {
    const key = sanitizeCommanderKey(p.commander_name);
    if (key) {
      playerCommanders[p.user_id] = key;
    }
  }

  // Fetch all user docs
  const allUserIds = [...new Set([...winnerUserIds, ...loserUserIds])];
  const userDocs = {};
  for (const uid of allUserIds) {
    const snap = await db.doc(`users/${uid}`).get();
    if (snap.exists) userDocs[uid] = snap.data();
  }

  // ELO calculation (K=32)
  const K = 32;
  const eloChanges = {};

  for (const uid of allUserIds) {
    eloChanges[uid] = 0;
  }

  // Each winner vs each loser
  for (const winnerId of winnerUserIds) {
    const winnerElo = (userDocs[winnerId]?.elo) || 1500;
    for (const loserId of loserUserIds) {
      const loserElo = (userDocs[loserId]?.elo) || 1500;

      const expectedWinner = 1.0 / (1.0 + Math.pow(10, (loserElo - winnerElo) / 400));
      const expectedLoser = 1.0 / (1.0 + Math.pow(10, (winnerElo - loserElo) / 400));

      eloChanges[winnerId] += K * (1 - expectedWinner);
      eloChanges[loserId] += K * (0 - expectedLoser);
    }
  }

  // Average changes (divide by number of opponents)
  for (const winnerId of winnerUserIds) {
    eloChanges[winnerId] = Math.round(eloChanges[winnerId] / loserUserIds.length);
  }
  for (const loserId of loserUserIds) {
    eloChanges[loserId] = Math.round(eloChanges[loserId] / winnerUserIds.length);
  }

  // Update user docs atomically
  const batch = db.batch();

  for (const uid of allUserIds) {
    const userRef = db.doc(`users/${uid}`);
    const currentElo = (userDocs[uid]?.elo) || 1500;
    const newElo = Math.max(0, currentElo + eloChanges[uid]);
    const isWinner = winnerUserIds.includes(uid);
    const commanderName = playerCommanders[uid];

    const updates = { elo: newElo };

    if (commanderName) {
      const deckStats = userDocs[uid]?.deck_stats || {};
      const currentDeck = deckStats[commanderName] || { elo: 1500, wins: 0, losses: 0, games: 0 };

      // Deck ELO uses same change as player ELO
      const newDeckElo = Math.max(0, currentDeck.elo + eloChanges[uid]);

      updates[`deck_stats.${commanderName}`] = {
        elo: newDeckElo,
        wins: currentDeck.wins + (isWinner ? 1 : 0),
        losses: currentDeck.losses + (isWinner ? 0 : 1),
        games: currentDeck.games + 1,
      };
    }

    batch.update(userRef, updates);
  }

  await batch.commit();
  console.log(`onGameFinished: Updated ELO for ${allUserIds.length} players in game ${gameId}`);
});
