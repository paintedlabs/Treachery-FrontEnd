import { test, expect, Page } from '@playwright/test';
import { getCurrentUserId, signInAsGuest } from './helpers';

/**
 * The privacy policy at /privacy.
 *
 * App Store Connect lists this URL, so it has to open for everyone.
 * AuthRedirect (app/_layout.tsx) sends signed-out visitors to /login and new
 * players to onboarding; the (public) route group is exempt from both. Each
 * test that expects no redirect also checks that the same redirect still fires
 * on a gated page, so a wait too short to see a redirect can't make it pass.
 */

// A page AuthRedirect guards that has no redirect of its own (unlike "/").
const GATED_PATH = '/create-game';

// AuthRedirect acts as soon as the auth state, and for a new player the
// profile check, resolves. This is how long a redirect gets to show up. The
// signed-out control counts it from page load, so it includes app start-up.
const REDIRECT_WINDOW_MS = 5_000;

// Firestore emulator REST API (port and project from ../firebase.json and
// scripts/emulators-exec.js). "Bearer owner" bypasses the security rules.
const USERS_URL = 'http://localhost:8087/v1/projects/demo-test/databases/(default)/documents/users';
const OWNER = { Authorization: 'Bearer owner' };

async function expectPolicy(page: Page) {
  await expect(page.getByRole('heading', { level: 1, name: 'Privacy Policy' })).toBeVisible();
  await expect(page).toHaveTitle('Treachery Privacy Policy');
}

/** Fails if anything moves the page off /privacy within the redirect window. */
async function expectToStayOnPolicy(page: Page) {
  await page.waitForTimeout(REDIRECT_WINDOW_MS);
  await expect(page).toHaveURL(/\/privacy$/);
  await expectPolicy(page);
}

/**
 * Deletes the player's profile, so the next page load treats them as a new
 * player: AuthProvider recreates the profile and sets isNewUser.
 */
async function deleteProfile(uid: string) {
  const response = await fetch(`${USERS_URL}/${uid}`, { method: 'DELETE', headers: OWNER });
  expect(response.ok).toBe(true);
}

async function profileExists(uid: string): Promise<boolean> {
  const response = await fetch(`${USERS_URL}/${uid}`, { headers: OWNER });
  return response.ok;
}

test.describe('Privacy policy', () => {
  test('opens for a signed-out visitor', async ({ page }) => {
    await page.goto('/privacy');
    await expectPolicy(page);
    await expectToStayOnPolicy(page);

    // Control: a gated page still sends the same visitor to sign in.
    await page.goto(GATED_PATH);
    await expect(page).toHaveURL(/\/login$/, { timeout: REDIRECT_WINDOW_MS });
  });

  test('opens for a new player without sending them to onboarding', async ({ page }) => {
    await page.goto('/login');
    await page.getByRole('button', { name: 'Play as Guest' }).click();
    await expect(page).toHaveURL(/\/onboarding\/display-name$/, { timeout: 20_000 });
    const uid = await getCurrentUserId(page);

    await deleteProfile(uid);
    await page.goto('/privacy');
    await expectPolicy(page);
    // Once the profile is back, the app treats this player as new.
    await expect.poll(() => profileExists(uid), { timeout: 10_000 }).toBe(true);
    await expectToStayOnPolicy(page);

    // Control: the same new-player load on a gated page goes to onboarding.
    await deleteProfile(uid);
    await page.goto(GATED_PATH);
    await expect.poll(() => profileExists(uid), { timeout: 10_000 }).toBe(true);
    await expect(page).toHaveURL(/\/onboarding\/display-name$/, { timeout: REDIRECT_WINDOW_MS });
  });

  test('opens for a signed-in player', async ({ page }) => {
    await signInAsGuest(page);
    await page.goto('/privacy');
    await expectPolicy(page);
    await expectToStayOnPolicy(page);
  });
});
