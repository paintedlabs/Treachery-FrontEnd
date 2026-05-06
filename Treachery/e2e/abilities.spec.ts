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

    // After the cloud function returns, the traitor's identity_card_id should
    // be the assassin's old card (assassin_01 from the seed cursor) and the
    // traitor's role should still be 'traitor'.
    await expect(async () => {
      const docs = await fetchPlayerDocs(traitor.page, gameId);
      const traitorDoc = docs.find((d) => d.user_id === traitor.userId);
      expect(traitorDoc?.identity_card_id).toBe(assassinA.identityCardId);
      expect(traitorDoc?.role).toBe('traitor'); // role doesn't change, only the card
      expect(traitorDoc?.is_face_down).toBe(true); // non-leader stolen card
      expect(traitorDoc?.original_identity_card_id).toBe('traitor_07');
    }).toPass({ timeout: 10_000 });

    // Sanity: we also still have unverified guests (assassinB and leader)
    // alive on the game board. Just confirm the traitor is no longer eliminated.
    const docs = await fetchPlayerDocs(traitor.page, gameId);
    const traitorDoc = docs.find((d) => d.user_id === traitor.userId);
    expect(traitorDoc?.is_eliminated).toBe(false);
    void assassinB; // unused, present for clarity
  });

  test('Puppet Master — redistribute identity cards among other players', async ({ browser }) => {
    const { players, gameId } = await setupSeededGame(
      browser,
      FOUR_PLAYER_LAYOUT,
      { cardOverrides: { 3: 'traitor_09' } }, // traitor gets The Puppet Master
    );
    const traitor = playerWithRole(players, 'traitor');
    const leader = playerWithRole(players, 'leader');
    const [assassinA, assassinB] = playersWithRole(players, 'assassin');

    // Traitor unveils — Puppet Master modal auto-opens with the other 3
    // players (host=leader, assassinA, assassinB) and their current cards.
    await unveilSelf(traitor.page);

    // Tap leader's row → tap assassinA's row → swaps their cards.
    // The modal labels each row with "Swap with {display_name}".
    const swapButtons = traitor.page.getByRole('button', { name: /^Swap with / });
    await expect(swapButtons.first()).toBeVisible({ timeout: 10_000 });

    // Match exactly 3 swap buttons (leader + 2 assassins; traitor excludes self).
    await expect(swapButtons).toHaveCount(3);
    // Tap first then second — swaps cards between players 1 and 2.
    await swapButtons.nth(0).click();
    await swapButtons.nth(1).click();

    await traitor.page.getByRole('button', { name: 'Confirm redistribution' }).click();

    // After resolution, exactly two of (leader, assassinA, assassinB) have
    // had their cards changed. We don't know the modal ordering, so just
    // assert that the multiset of identity_card_ids on those three players
    // is unchanged but their pairings have shifted.
    await expect(async () => {
      const docs = await fetchPlayerDocs(traitor.page, gameId);
      const others = [leader, assassinA, assassinB].map((p) =>
        docs.find((d) => d.user_id === p.userId),
      );
      // Original cards were leader.identityCardId + 2 assassin cards.
      const originalCards = new Set([
        leader.identityCardId,
        assassinA.identityCardId,
        assassinB.identityCardId,
      ]);
      const currentCards = new Set(others.map((d) => d?.identity_card_id));
      // Multiset preserved.
      expect(currentCards).toEqual(originalCards);
      // ≥1 player has a different card from where they started (a swap occurred).
      const swappedCount = others.filter(
        (d, i) =>
          d?.identity_card_id !== [leader, assassinA, assassinB][i].identityCardId,
      ).length;
      expect(swappedCount).toBeGreaterThan(0);
      // Each non-leader card that was reassigned is now is_face_down.
      for (const d of others) {
        if (d?.identity_card_id !== d?.original_identity_card_id && d?.original_identity_card_id) {
          // Card changed — non-leader cards should be face down.
          if (d?.identity_card_id?.startsWith('leader_') === false) {
            expect(d?.is_face_down).toBe(true);
          }
        }
      }
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
