'use strict';

/**
 * INTEGRATION: the three "special" traitor callables —
 *   exports.resolveMetamorph      (The Metamorph,       traitor_07)
 *   exports.resolvePuppetMaster   (The Puppet Master,   traitor_09)
 *   exports.resolveWearerOfMasks  (The Wearer of Masks, traitor_13)
 *
 * Games are set up through the real startGame testSeed hook, then advanced
 * with the real unveilPlayer / adjustLife callables wherever the rules allow
 * it. firebase-admin is used to force a state the rules cannot reach on their
 * own (e.g. an eliminated Leader in a game that has not finished).
 */

const { describe, it, after } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

after(async () => {
  await h.shutdown();
});

const LEADER = { role: 'leader', card: 'leader_01' };
const ASSASSIN_A = { role: 'assassin', card: 'assassin_01' };
const ASSASSIN_B = { role: 'assassin', card: 'assassin_02' };

/** 4-player game whose single traitor holds `traitorCard`. */
async function gameWithTraitor(traitorCard) {
  const users = await h.getUsers(4);
  const game = await h.seedStartedGame({
    users,
    seats: [LEADER, ASSASSIN_A, ASSASSIN_B, { role: 'traitor', card: traitorCard }],
  });
  return { ...game, traitor: users[3] };
}

/**
 * Eliminates a player through the real adjustLife callable. Callers must pick
 * a seat whose removal does not satisfy a win condition, or the game finishes.
 */
function eliminate(game, playerId) {
  return game.users[0].call('adjustLife', {
    gameId: game.gameId,
    playerId,
    amount: -1000,
  });
}

// ════════════════════════════════════════════════════════════════
// The Metamorph — traitor_07
// ════════════════════════════════════════════════════════════════

describe('resolveMetamorph — guards', () => {
  it("rejects a caller whose card is not The Metamorph", async () => {
    const game = await gameWithTraitor('traitor_01');
    await game.traitor.call('unveilPlayer', { gameId: game.gameId });
    await eliminate(game, 'p2');

    await h.expectHttpsError(
      game.traitor.call('resolveMetamorph', {
        gameId: game.gameId,
        targetPlayerId: 'p2',
      }),
      'failed-precondition'
    );
  });

  it('rejects a Metamorph who has not unveiled', async () => {
    const game = await gameWithTraitor('traitor_07');
    await eliminate(game, 'p2');

    await h.expectHttpsError(
      game.traitor.call('resolveMetamorph', {
        gameId: game.gameId,
        targetPlayerId: 'p2',
      }),
      'failed-precondition'
    );
  });

  it('rejects a target who is still alive', async () => {
    const game = await gameWithTraitor('traitor_07');
    await game.traitor.call('unveilPlayer', { gameId: game.gameId });

    await h.expectHttpsError(
      game.traitor.call('resolveMetamorph', {
        gameId: game.gameId,
        targetPlayerId: 'p1',
      }),
      'failed-precondition'
    );
  });

  it("rejects stealing the Leader's identity", async () => {
    const game = await gameWithTraitor('traitor_07');
    await game.traitor.call('unveilPlayer', { gameId: game.gameId });
    // Seeded directly: eliminating the Leader for real would immediately end
    // the game, and this test is about the Leader-card guard, not win state.
    await h.patchPlayer(game.gameId, 'p0', {
      is_eliminated: true,
      is_unveiled: true,
      life_total: 0,
    });

    await h.expectHttpsError(
      game.traitor.call('resolveMetamorph', {
        gameId: game.gameId,
        targetPlayerId: 'p0',
      }),
      'failed-precondition'
    );
    const metamorph = await h.getPlayer(game.gameId, 'p3');
    assert.equal(metamorph.identity_card_id, 'traitor_07');
    assert.equal(metamorph.role, 'traitor');
  });

  it('rejects an unknown target', async () => {
    const game = await gameWithTraitor('traitor_07');
    await game.traitor.call('unveilPlayer', { gameId: game.gameId });
    await h.expectHttpsError(
      game.traitor.call('resolveMetamorph', {
        gameId: game.gameId,
        targetPlayerId: 'nope',
      }),
      'not-found'
    );
  });

  it('rejects a missing targetPlayerId', async () => {
    const game = await gameWithTraitor('traitor_07');
    await h.expectHttpsError(
      game.traitor.call('resolveMetamorph', { gameId: game.gameId }),
      'invalid-argument'
    );
  });

  it('rejects a caller who is not in the game', async () => {
    const users = await h.getUsers(5);
    const game = await h.seedStartedGame({
      users: users.slice(0, 4),
      seats: [LEADER, ASSASSIN_A, ASSASSIN_B, { role: 'traitor', card: 'traitor_07' }],
    });
    await h.expectHttpsError(
      users[4].call('resolveMetamorph', { gameId: game.gameId, targetPlayerId: 'p2' }),
      'not-found'
    );
  });

  it('rejects use before the game is in progress', async () => {
    const users = await h.getUsers(4);
    const game = await h.seedGame({ users });
    await h.expectHttpsError(
      users[3].call('resolveMetamorph', { gameId: game.gameId, targetPlayerId: 'p2' }),
      'failed-precondition'
    );
  });

  it('rejects an unauthenticated caller', async () => {
    const game = await gameWithTraitor('traitor_07');
    await h.expectHttpsError(
      h.unauthenticatedCaller()('resolveMetamorph', {
        gameId: game.gameId,
        targetPlayerId: 'p2',
      }),
      'unauthenticated'
    );
  });
});

describe('resolveMetamorph — stealing an eliminated identity', () => {
  it("adopts the target's card AND role", async () => {
    const game = await gameWithTraitor('traitor_07');
    await game.traitor.call('unveilPlayer', { gameId: game.gameId });
    await eliminate(game, 'p2');

    const res = await game.traitor.call('resolveMetamorph', {
      gameId: game.gameId,
      targetPlayerId: 'p2',
    });
    assert.equal(res.success, true);
    assert.equal(res.newCardId, 'assassin_02');
    assert.equal(res.isFaceDown, true);

    const metamorph = await h.getPlayer(game.gameId, 'p3');
    assert.equal(metamorph.identity_card_id, 'assassin_02');
    assert.equal(metamorph.role, 'assassin', 'the role follows the stolen card');
    assert.equal(metamorph.is_face_down, true);
    assert.equal(metamorph.original_identity_card_id, 'traitor_07');
    assert.equal(metamorph.original_role, 'traitor');
  });

  // SKIP: currently broken — see finding #D. Un-skip when functions/index.js is fixed.
  //
  // resolveMetamorph (index.js ~857) only writes the caller's doc; the target
  // keeps its identity_card_id, so the stolen card exists twice on the table.
  // Two players holding the same identity corrupts every downstream reader
  // (Puppet Master's "already assigned" guard, Wearer of Masks' "already in
  // the game" guard, and the win-condition role tally).
  it(
    'leaves exactly one copy of every identity card in play',
    async () => {
      const game = await gameWithTraitor('traitor_07');
      await game.traitor.call('unveilPlayer', { gameId: game.gameId });
      await eliminate(game, 'p2');

      await game.traitor.call('resolveMetamorph', {
        gameId: game.gameId,
        targetPlayerId: 'p2',
      });

      const players = await h.getPlayers(game.gameId);
      const cardIds = players.map((p) => p.identity_card_id).filter(Boolean);
      assert.equal(
        new Set(cardIds).size,
        cardIds.length,
        `no two players may hold the same identity card, got ${cardIds.join(', ')}`
      );
    }
  );

  // SKIP: currently broken — see finding #D. Un-skip when functions/index.js is fixed.
  //
  // There is no is_eliminated guard on the caller. Elimination sets
  // is_unveiled = true, so a dead Metamorph sails straight through the only
  // gate the function has and steals a card from beyond the grave.
  it(
    'cannot be used by an eliminated Metamorph',
    async () => {
      const game = await gameWithTraitor('traitor_07');
      await game.traitor.call('unveilPlayer', { gameId: game.gameId });
      await eliminate(game, 'p2');
      await eliminate(game, 'p3');

      await h.expectHttpsError(
        game.traitor.call('resolveMetamorph', {
          gameId: game.gameId,
          targetPlayerId: 'p2',
        }),
        'failed-precondition'
      );
      const metamorph = await h.getPlayer(game.gameId, 'p3');
      assert.equal(metamorph.identity_card_id, 'traitor_07');
    }
  );
});

// ════════════════════════════════════════════════════════════════
// The Puppet Master — traitor_09
// ════════════════════════════════════════════════════════════════

async function unveiledPuppetMaster() {
  const game = await gameWithTraitor('traitor_09');
  await game.traitor.call('unveilPlayer', { gameId: game.gameId });
  return game;
}

describe('resolvePuppetMaster — guards', () => {
  it('rejects a caller whose card is not The Puppet Master', async () => {
    const game = await gameWithTraitor('traitor_01');
    await game.traitor.call('unveilPlayer', { gameId: game.gameId });
    await h.expectHttpsError(
      game.traitor.call('resolvePuppetMaster', {
        gameId: game.gameId,
        redistributions: { p1: 'assassin_02', p2: 'assassin_01' },
      }),
      'failed-precondition'
    );
  });

  it('rejects a Puppet Master who has not unveiled', async () => {
    const game = await gameWithTraitor('traitor_09');
    await h.expectHttpsError(
      game.traitor.call('resolvePuppetMaster', {
        gameId: game.gameId,
        redistributions: { p1: 'assassin_02', p2: 'assassin_01' },
      }),
      'failed-precondition'
    );
  });

  it('rejects redistributing the caller\'s own card', async () => {
    const game = await unveiledPuppetMaster();
    await h.expectHttpsError(
      game.traitor.call('resolvePuppetMaster', {
        gameId: game.gameId,
        redistributions: { p3: 'assassin_01' },
      }),
      'failed-precondition'
    );
  });

  it('rejects redistributing to an eliminated player', async () => {
    const game = await unveiledPuppetMaster();
    await eliminate(game, 'p2');
    await h.expectHttpsError(
      game.traitor.call('resolvePuppetMaster', {
        gameId: game.gameId,
        redistributions: { p2: 'assassin_01' },
      }),
      'failed-precondition'
    );
  });

  it('rejects handing the same card to two players', async () => {
    const game = await unveiledPuppetMaster();
    await h.expectHttpsError(
      game.traitor.call('resolvePuppetMaster', {
        gameId: game.gameId,
        redistributions: { p1: 'assassin_01', p2: 'assassin_01' },
      }),
      'failed-precondition'
    );
    const players = await h.getPlayers(game.gameId);
    assert.equal(players[1].identity_card_id, 'assassin_01');
    assert.equal(players[2].identity_card_id, 'assassin_02');
  });

  it('rejects an unknown player id', async () => {
    const game = await unveiledPuppetMaster();
    await h.expectHttpsError(
      game.traitor.call('resolvePuppetMaster', {
        gameId: game.gameId,
        redistributions: { ghost: 'assassin_01' },
      }),
      'not-found'
    );
  });

  it('rejects a missing redistributions map', async () => {
    const game = await unveiledPuppetMaster();
    await h.expectHttpsError(
      game.traitor.call('resolvePuppetMaster', { gameId: game.gameId }),
      'invalid-argument'
    );
  });

  it('rejects use before the game is in progress', async () => {
    const users = await h.getUsers(4);
    const game = await h.seedGame({ users });
    await h.expectHttpsError(
      users[3].call('resolvePuppetMaster', {
        gameId: game.gameId,
        redistributions: { p1: 'assassin_01' },
      }),
      'failed-precondition'
    );
  });

  it('rejects an unauthenticated caller', async () => {
    const game = await unveiledPuppetMaster();
    await h.expectHttpsError(
      h.unauthenticatedCaller()('resolvePuppetMaster', {
        gameId: game.gameId,
        redistributions: { p1: 'assassin_02', p2: 'assassin_01' },
      }),
      'unauthenticated'
    );
  });
});

describe('resolvePuppetMaster — redistribution', () => {
  it('swaps two in-play identities and carries the roles with them', async () => {
    const game = await unveiledPuppetMaster();

    const res = await game.traitor.call('resolvePuppetMaster', {
      gameId: game.gameId,
      redistributions: { p1: 'assassin_02', p2: 'assassin_01' },
    });
    assert.deepEqual(res, { success: true });

    const players = await h.getPlayers(game.gameId);
    assert.equal(players[1].identity_card_id, 'assassin_02');
    assert.equal(players[1].role, 'assassin');
    assert.equal(players[1].is_face_down, true);
    assert.equal(players[1].original_identity_card_id, 'assassin_01');
    assert.equal(players[1].original_role, 'assassin');

    assert.equal(players[2].identity_card_id, 'assassin_01');
    assert.equal(players[2].original_identity_card_id, 'assassin_02');

    assert.equal(players[0].identity_card_id, 'leader_01', 'the Leader is untouched');
    assert.equal(players[3].identity_card_id, 'traitor_09', 'the caller keeps their card');
  });

  // SKIP: currently broken — see finding #C. Un-skip when functions/index.js is fixed.
  //
  // resolvePuppetMaster (index.js ~922) accepts ANY id from identityCards.json.
  // The card only has to exist — it does not have to be in the game — so the
  // Puppet Master can conjure the other ~58 identities out of the box.
  it(
    'rejects assigning a card that is not currently in play',
    async () => {
      const game = await unveiledPuppetMaster();

      await h.expectHttpsError(
        game.traitor.call('resolvePuppetMaster', {
          gameId: game.gameId,
          redistributions: { p1: 'assassin_15' },
        }),
        'invalid-argument'
      );
      const p1 = await h.getPlayer(game.gameId, 'p1');
      assert.equal(p1.identity_card_id, 'assassin_01');
    }
  );

  // SKIP: currently broken — see finding #C. Un-skip when functions/index.js is fixed.
  //
  // Nothing checks that the result is a permutation of the identities already
  // on the table, so the Leader's card can be duplicated onto a second player
  // and the game ends up with two Leaders.
  it(
    'rejects creating a second Leader',
    async () => {
      const game = await unveiledPuppetMaster();

      await h.expectHttpsError(
        game.traitor.call('resolvePuppetMaster', {
          gameId: game.gameId,
          redistributions: { p1: 'leader_01' },
        }),
        'invalid-argument'
      );
      const players = await h.getPlayers(game.gameId);
      assert.equal(
        players.filter((p) => p.role === 'leader').length,
        1,
        'a game must never contain two Leaders'
      );
    }
  );

  // SKIP: currently broken — see finding #C. Un-skip when functions/index.js is fixed.
  //
  // The mirror image: the Leader can be handed a non-Leader identity, which
  // silently deletes the Leader from the game and hands the assassins the win
  // on the next elimination check.
  it(
    'rejects turning the Leader into a non-Leader',
    async () => {
      const game = await unveiledPuppetMaster();

      await h.expectHttpsError(
        game.traitor.call('resolvePuppetMaster', {
          gameId: game.gameId,
          redistributions: { p0: 'assassin_01' },
        }),
        'invalid-argument'
      );
      const leader = await h.getPlayer(game.gameId, 'p0');
      assert.equal(leader.role, 'leader');
      assert.equal(leader.identity_card_id, 'leader_01');
    }
  );

  // SKIP: currently broken — see finding #C. Un-skip when functions/index.js is fixed.
  //
  // There is no is_eliminated guard on the caller, and elimination sets
  // is_unveiled = true, so the only gate the function has is already satisfied.
  it(
    'cannot be used by an eliminated Puppet Master',
    async () => {
      const game = await unveiledPuppetMaster();
      await eliminate(game, 'p3');

      await h.expectHttpsError(
        game.traitor.call('resolvePuppetMaster', {
          gameId: game.gameId,
          redistributions: { p1: 'assassin_02', p2: 'assassin_01' },
        }),
        'failed-precondition'
      );
      const players = await h.getPlayers(game.gameId);
      assert.equal(players[1].identity_card_id, 'assassin_01');
      assert.equal(players[2].identity_card_id, 'assassin_02');
    }
  );

  // SKIP: currently broken — see finding #C. Un-skip when functions/index.js is fixed.
  //
  // The Puppet Master's unveil ability is a one-shot, but nothing records that
  // it has been used, so it can be replayed for the rest of the game.
  it(
    'can only be resolved once',
    async () => {
      const game = await unveiledPuppetMaster();

      await game.traitor.call('resolvePuppetMaster', {
        gameId: game.gameId,
        redistributions: { p1: 'assassin_02', p2: 'assassin_01' },
      });

      await h.expectHttpsError(
        game.traitor.call('resolvePuppetMaster', {
          gameId: game.gameId,
          redistributions: { p1: 'assassin_01', p2: 'assassin_02' },
        }),
        'failed-precondition'
      );
    }
  );
});

// ════════════════════════════════════════════════════════════════
// The Wearer of Masks — traitor_13
// ════════════════════════════════════════════════════════════════

async function unveiledWearer() {
  const game = await gameWithTraitor('traitor_13');
  await game.traitor.call('unveilPlayer', { gameId: game.gameId });
  return game;
}

describe('resolveWearerOfMasks', () => {
  it('becomes a card from outside the game while staying a traitor', async () => {
    const game = await unveiledWearer();

    const res = await game.traitor.call('resolveWearerOfMasks', {
      gameId: game.gameId,
      chosenCardId: 'assassin_15',
    });
    assert.deepEqual(res, { success: true, newCardId: 'assassin_15' });

    const wearer = await h.getPlayer(game.gameId, 'p3');
    assert.equal(wearer.identity_card_id, 'assassin_15');
    assert.equal(wearer.role, 'traitor', 'the Wearer of Masks stays a traitor');
    assert.equal(wearer.original_identity_card_id, 'traitor_13');
  });

  it('accepts declining the ability', async () => {
    const game = await unveiledWearer();
    const res = await game.traitor.call('resolveWearerOfMasks', {
      gameId: game.gameId,
      chosenCardId: null,
    });
    assert.deepEqual(res, { success: true, declined: true });

    const wearer = await h.getPlayer(game.gameId, 'p3');
    assert.equal(wearer.identity_card_id, 'traitor_13');
  });

  it('rejects a Leader card', async () => {
    const game = await unveiledWearer();
    await h.expectHttpsError(
      game.traitor.call('resolveWearerOfMasks', {
        gameId: game.gameId,
        chosenCardId: 'leader_02',
      }),
      'failed-precondition'
    );
  });

  it('rejects a card that is already in the game', async () => {
    const game = await unveiledWearer();
    await h.expectHttpsError(
      game.traitor.call('resolveWearerOfMasks', {
        gameId: game.gameId,
        chosenCardId: 'assassin_01',
      }),
      'failed-precondition'
    );
  });

  it('rejects a card id that does not exist', async () => {
    const game = await unveiledWearer();
    await h.expectHttpsError(
      game.traitor.call('resolveWearerOfMasks', {
        gameId: game.gameId,
        chosenCardId: 'assassin_99',
      }),
      'not-found'
    );
  });

  it('rejects a caller whose card is not The Wearer of Masks', async () => {
    const game = await gameWithTraitor('traitor_01');
    await game.traitor.call('unveilPlayer', { gameId: game.gameId });
    await h.expectHttpsError(
      game.traitor.call('resolveWearerOfMasks', {
        gameId: game.gameId,
        chosenCardId: 'assassin_15',
      }),
      'failed-precondition'
    );
  });

  it('rejects a Wearer who has not unveiled', async () => {
    const game = await gameWithTraitor('traitor_13');
    await h.expectHttpsError(
      game.traitor.call('resolveWearerOfMasks', {
        gameId: game.gameId,
        chosenCardId: 'assassin_15',
      }),
      'failed-precondition'
    );
  });

  it('rejects an unauthenticated caller', async () => {
    const game = await unveiledWearer();
    await h.expectHttpsError(
      h.unauthenticatedCaller()('resolveWearerOfMasks', {
        gameId: game.gameId,
        chosenCardId: 'assassin_15',
      }),
      'unauthenticated'
    );
  });

  // SKIP: currently broken — see finding #E. Un-skip when functions/index.js is fixed.
  //
  // resolveWearerOfMasks (index.js ~1007) only blocks Leader cards and cards
  // already in play. traitor_09 is neither, so the Wearer can simply *become*
  // The Puppet Master — and resolvePuppetMaster's sole identity gate is
  // `identity_card_id === "traitor_09"`, which now passes. One unveil turns
  // into the strongest table-warping ability in the game.
  it(
    'copying traitor_09 must not grant Puppet Master powers',
    async () => {
      const game = await unveiledWearer();

      let escalated = false;
      try {
        await game.traitor.call('resolveWearerOfMasks', {
          gameId: game.gameId,
          chosenCardId: 'traitor_09',
        });
        await game.traitor.call('resolvePuppetMaster', {
          gameId: game.gameId,
          redistributions: { p1: 'assassin_02', p2: 'assassin_01' },
        });
        escalated = true;
      } catch {
        // Blocked at one of the two steps — that is the correct behaviour.
      }

      assert.equal(
        escalated,
        false,
        'becoming traitor_09 via Wearer of Masks must not unlock resolvePuppetMaster'
      );
      const players = await h.getPlayers(game.gameId);
      assert.equal(players[1].identity_card_id, 'assassin_01');
      assert.equal(players[2].identity_card_id, 'assassin_02');
    }
  );

  it('rejects a caller who was not originally The Wearer of Masks', async () => {
    const game = await unveiledWearer();
    await h.patchPlayer(game.gameId, 'p3', { original_identity_card_id: 'assassin_01' });
    await h.expectHttpsError(
      game.traitor.call('resolveWearerOfMasks', {
        gameId: game.gameId,
        chosenCardId: 'assassin_15',
      }),
      'failed-precondition'
    );
  });
});
