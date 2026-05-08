import { test, expect } from '@playwright/test';
import {
  setupSeededGame,
  playerWithRole,
  playersWithRole,
  forfeit,
  unveilSelf,
  fetchPlayerDocs,
  Role,
} from './helpers';

/**
 * Ability tests: drive each of the three traitor-card resolution flows
 * through the real production UI (the AbilityResolver modal that
 * auto-opens after unveil for traitor_07/_09/_13).
 *
 * Each test seeds the traitor onto a specific identity card via the
 * emulator-only testSeed, plays through the unveil + ability modal, and
 * asserts the resulting Firestore state directly.
 */

const FOUR_PLAYER_LAYOUT: Role[] = ['leader', 'assassin', 'assassin', 'traitor'];

test.describe('Traitor abilities', () => {
  test('Metamorph — steal an eliminated opponent\'s identity card', async ({ browser }) => {
    const { players, gameId } = await setupSeededGame(
      browser,
      FOUR_PLAYER_LAYOUT,
      { cardOverrides: { 3: 'traitor_07' } }, // traitor gets The Metamorph
    );
    const traitor = playerWithRole(players, 'traitor');
    const [assassinA, assassinB] = playersWithRole(players, 'assassin');

    // Eliminate one assassin first so the Metamorph has someone to steal from.
    await forfeit(assassinA.page);
    await expect(assassinA.page).toHaveURL(/\/game-over\//, { timeout: 15_000 });

    // Wait for the elimination to propagate to the traitor's Firestore view
    // before unveiling — otherwise the modal opens with an empty target list.
    await expect(async () => {
      const docs = await fetchPlayerDocs(traitor.page, gameId);
      const a = docs.find((d) => d.user_id === assassinA.userId);
      expect(a?.is_eliminated).toBe(true);
    }).toPass({ timeout: 10_000 });

    // Traitor unveils — AbilityResolver modal auto-opens.
    await unveilSelf(traitor.page);

    // Modal renders with the eliminated assassin as the only target.
    await expect(traitor.page.getByRole('button', { name: /^Steal from / })).toBeVisible({ timeout: 10_000 });
    await traitor.page.getByRole('button', { name: /^Steal from / }).first().click();
    await traitor.page.getByRole('button', { name: 'Steal identity' }).click();

    // After the cloud function returns, the traitor "gains control of that
    // player's identity card" — they BECOME the stolen identity, so role
    // follows the stolen card. (Original role is preserved for game-over.)
    await expect(async () => {
      const docs = await fetchPlayerDocs(traitor.page, gameId);
      const traitorDoc = docs.find((d) => d.user_id === traitor.userId);
      expect(traitorDoc?.identity_card_id).toBe(assassinA.identityCardId);
      expect(traitorDoc?.role).toBe('assassin'); // role follows the stolen card
      expect(traitorDoc?.is_face_down).toBe(true); // non-leader stolen card
      expect(traitorDoc?.original_identity_card_id).toBe('traitor_07');
      expect(traitorDoc?.original_role).toBe('traitor');
    }).toPass({ timeout: 10_000 });

    // Sanity: we also still have unverified guests (assassinB and leader)
    // alive on the game board. Just confirm the traitor is no longer eliminated.
    const docs = await fetchPlayerDocs(traitor.page, gameId);
    const traitorDoc = docs.find((d) => d.user_id === traitor.userId);
    expect(traitorDoc?.is_eliminated).toBe(false);
    void assassinB; // unused, present for clarity
  });

  test('Puppet Master — redistribute identity cards among other players', async ({ browser }) => {
    // Regression for the staging bug where a Puppet Master swap moved the
    // identity *card* but left `player.role` untouched, so the lobby/score
    // UI showed stale roles and `checkWinConditions` would fire on the wrong
    // role mapping. After this test passes, role follows the card.
    const { players, gameId } = await setupSeededGame(
      browser,
      FOUR_PLAYER_LAYOUT,
      { cardOverrides: { 3: 'traitor_09' } }, // traitor gets The Puppet Master
    );
    const traitor = playerWithRole(players, 'traitor');
    const leader = playerWithRole(players, 'leader');
    const [assassinA, assassinB] = playersWithRole(players, 'assassin');

    // Traitor unveils — Puppet Master modal auto-opens. The modal shows one
    // "Swap with {display_name}" button per non-traitor (3 buttons total).
    await unveilSelf(traitor.page);
    await expect(traitor.page.getByRole('button', { name: /^Swap with / })).toHaveCount(3, { timeout: 10_000 });

    // Target the leader and assassinA explicitly (rather than relying on
    // modal order). Tapping their two rows swaps their cards.
    await traitor.page.getByRole('button', { name: `Swap with ${leader.name}` }).click();
    await traitor.page.getByRole('button', { name: `Swap with ${assassinA.name}` }).click();
    await traitor.page.getByRole('button', { name: 'Confirm redistribution' }).click();

    // After resolution: leader holds assassinA's card and BECOMES an
    // assassin (role follows card). assassinA holds the leader card and
    // BECOMES the leader. assassinB is untouched. Original roles are
    // preserved on both swapped players.
    await expect(async () => {
      const docs = await fetchPlayerDocs(traitor.page, gameId);
      const leaderDoc = docs.find((d) => d.user_id === leader.userId);
      const assassinADoc = docs.find((d) => d.user_id === assassinA.userId);
      const assassinBDoc = docs.find((d) => d.user_id === assassinB.userId);

      // Cards swapped.
      expect(leaderDoc?.identity_card_id).toBe(assassinA.identityCardId);
      expect(assassinADoc?.identity_card_id).toBe(leader.identityCardId);
      expect(assassinBDoc?.identity_card_id).toBe(assassinB.identityCardId);

      // Roles followed the cards — this is what the staging bug got wrong.
      expect(leaderDoc?.role).toBe('assassin');
      expect(assassinADoc?.role).toBe('leader');
      expect(assassinBDoc?.role).toBe('assassin');

      // Original roles preserved for game-over reveal.
      expect(leaderDoc?.original_role).toBe('leader');
      expect(assassinADoc?.original_role).toBe('assassin');
      // Untouched player has no original_role recorded (no swap happened).
      expect(assassinBDoc?.original_role ?? null).toBe(null);

      // The non-Leader card given to the original leader is face-down per
      // the rules ("Then turn face down each of those cards that isn't a
      // Leader"). The Leader card given to the assassin stays face-up.
      expect(leaderDoc?.is_face_down).toBe(true);
      expect(assassinADoc?.is_face_down).toBe(false);
    }).toPass({ timeout: 10_000 });
  });

  test('Wearer of Masks — become a copy of a chosen non-Leader card', async ({ browser }) => {
    const { players, gameId } = await setupSeededGame(
      browser,
      FOUR_PLAYER_LAYOUT,
      { cardOverrides: { 3: 'traitor_13' } }, // traitor gets The Wearer of Masks
    );
    const traitor = playerWithRole(players, 'traitor');

    // Traitor unveils — Wearer of Masks modal auto-opens with the X picker.
    await unveilSelf(traitor.page);

    // Default X is 3. Click "Reveal Cards" → 3 random non-leader cards appear.
    await expect(traitor.page.getByRole('button', { name: 'Reveal cards' })).toBeVisible({ timeout: 10_000 });
    await traitor.page.getByRole('button', { name: 'Reveal cards' }).click();

    // Pick the first revealed card (each has a "Pick identity <card name>" label).
    const chooseButtons = traitor.page.getByRole('button', { name: /^Pick identity / });
    await expect(chooseButtons.first()).toBeVisible({ timeout: 10_000 });
    await chooseButtons.first().click();

    await traitor.page.getByRole('button', { name: 'Become this identity' }).click();

    // Verify the traitor's card changed and role is still 'traitor'.
    await expect(async () => {
      const docs = await fetchPlayerDocs(traitor.page, gameId);
      const traitorDoc = docs.find((d) => d.user_id === traitor.userId);
      expect(traitorDoc?.identity_card_id).not.toBe('traitor_13'); // it changed
      expect(traitorDoc?.identity_card_id).not.toBeNull();
      expect(traitorDoc?.role).toBe('traitor'); // role stays
      expect(traitorDoc?.original_identity_card_id).toBe('traitor_13');
      // The new card is not a leader card (Wearer of Masks rule).
      expect(traitorDoc?.identity_card_id?.startsWith('leader_')).toBe(false);
    }).toPass({ timeout: 10_000 });
  });
});
