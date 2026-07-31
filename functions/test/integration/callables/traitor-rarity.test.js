'use strict';

/**
 * INTEGRATION: max_traitor_rarity cap (startGame + updateGameSettings)
 *
 * The cap is statistical by nature, so the capped cases are run over many
 * real games rather than a single draw.
 */

const { describe, it, after } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

after(async () => {
  await h.shutdown();
});

const SEATS_4P = 4;
const ROUNDS = 25;
const CHUNK = 5;

/**
 * Starts `rounds` independent 4-player games (in small parallel batches so the
 * emulator is not hammered) and returns the traitor's identity card from each.
 */
async function drawTraitors(rounds, { maxTraitorRarity } = {}) {
  const users = await h.getUsers(SEATS_4P);
  const drawn = [];

  for (let start = 0; start < rounds; start += CHUNK) {
    const size = Math.min(CHUNK, rounds - start);
    // eslint-disable-next-line no-await-in-loop
    const games = await Promise.all(
      Array.from({ length: size }, () => h.seedGame({ users, maxTraitorRarity }))
    );
    // eslint-disable-next-line no-await-in-loop
    await Promise.all(
      games.map((g) => g.host.call('startGame', { gameId: g.gameId }))
    );
    // eslint-disable-next-line no-await-in-loop
    const rosters = await Promise.all(games.map((g) => h.getPlayers(g.gameId)));
    for (const players of rosters) {
      const traitors = players.filter((p) => p.role === 'traitor');
      assert.equal(traitors.length, 1, 'a 4-player game has exactly one traitor');
      drawn.push(traitors[0].identity_card_id);
    }
  }
  return drawn;
}

describe('max_traitor_rarity — startGame honours the cap', () => {
  it(`caps the traitor pool to the 4 uncommon traitors over ${ROUNDS} games`, async () => {
    const drawn = await drawTraitors(ROUNDS, { maxTraitorRarity: 'uncommon' });
    assert.equal(drawn.length, ROUNDS);
    for (const cardId of drawn) {
      assert.ok(
        h.UNCOMMON_TRAITORS.includes(cardId),
        `traitor ${cardId} (rarity ${h.cardById(cardId)?.rarity}) exceeds the "uncommon" cap`
      );
    }
  });

  it(`caps the traitor pool to uncommon+rare over ${ROUNDS} games`, async () => {
    const drawn = await drawTraitors(ROUNDS, { maxTraitorRarity: 'rare' });
    assert.equal(drawn.length, ROUNDS);
    for (const cardId of drawn) {
      const rarity = h.cardById(cardId)?.rarity;
      assert.ok(
        ['uncommon', 'rare'].includes(rarity),
        `traitor ${cardId} has rarity "${rarity}", which exceeds the "rare" cap`
      );
    }
  });

  it(`draws from the full traitor pool when no cap is set (${ROUNDS} games)`, async () => {
    const drawn = await drawTraitors(ROUNDS);
    assert.equal(drawn.length, ROUNDS);
    for (const cardId of drawn) {
      const card = h.cardById(cardId);
      assert.ok(card && card.role === 'traitor', `${cardId} must be a traitor card`);
    }
    // 9 of the 13 traitors are above uncommon; the odds of never drawing one of
    // them in 25 uncapped games are (4/13)^25 ~= 3e-13, so this is a safe
    // assertion that the cap is genuinely absent rather than silently applied.
    const sawHigherRarity = drawn.some(
      (id) => !h.UNCOMMON_TRAITORS.includes(id)
    );
    assert.ok(
      sawHigherRarity,
      `expected at least one non-uncommon traitor across ${ROUNDS} uncapped games, got ${drawn.join(', ')}`
    );
  });

  it('honours a cap that the host set through updateGameSettings', async () => {
    const users = await h.getUsers(SEATS_4P);
    const game = await h.seedGame({ users });

    await game.host.call('updateGameSettings', {
      gameId: game.gameId,
      maxTraitorRarity: 'uncommon',
    });
    const beforeStart = await h.getGame(game.gameId);
    assert.equal(beforeStart.max_traitor_rarity, 'uncommon');

    await game.host.call('startGame', { gameId: game.gameId });

    const players = await h.getPlayers(game.gameId);
    const traitor = players.find((p) => p.role === 'traitor');
    assert.ok(
      h.UNCOMMON_TRAITORS.includes(traitor.identity_card_id),
      `traitor ${traitor.identity_card_id} exceeds the cap set via updateGameSettings`
    );
  });
});

describe('max_traitor_rarity — updateGameSettings validation', () => {
  for (const rarity of ['uncommon', 'rare', 'mythic', 'special']) {
    it(`accepts and persists "${rarity}"`, async () => {
      const users = await h.getUsers(2);
      const game = await h.seedGame({ users });
      await game.host.call('updateGameSettings', {
        gameId: game.gameId,
        maxTraitorRarity: rarity,
      });
      const g = await h.getGame(game.gameId);
      assert.equal(g.max_traitor_rarity, rarity);
    });
  }

  for (const bad of ['common', 'SPECIAL', 'constructor', 'toString', '', 'legendary']) {
    it(`rejects ${JSON.stringify(bad)} with invalid-argument`, async () => {
      const users = await h.getUsers(2);
      const game = await h.seedGame({ users });
      await h.expectHttpsError(
        game.host.call('updateGameSettings', {
          gameId: game.gameId,
          maxTraitorRarity: bad,
        }),
        'invalid-argument'
      );
      const g = await h.getGame(game.gameId);
      assert.equal(
        g.max_traitor_rarity,
        undefined,
        'a rejected rarity must not be written'
      );
    });
  }

  for (const bad of [123, null, true]) {
    it(`rejects the non-string value ${JSON.stringify(bad)}`, async () => {
      const users = await h.getUsers(2);
      const game = await h.seedGame({ users });
      await h.expectHttpsError(
        game.host.call('updateGameSettings', {
          gameId: game.gameId,
          maxTraitorRarity: bad,
        }),
        'invalid-argument'
      );
    });
  }
});
