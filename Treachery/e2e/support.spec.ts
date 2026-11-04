import { test, expect, Page } from '@playwright/test';
import { CONTACT_EMAIL } from '../src/constants/operator';
import { signInAsGuest } from './helpers';

/**
 * The support page at /support.
 *
 * App Store Connect lists this URL as the app's Support URL, so it has to open
 * for everyone. AuthRedirect (app/_layout.tsx) sends signed-out visitors to
 * /login; the (public) route group is exempt, as privacy.spec.ts checks in more
 * detail for the privacy policy.
 */

// A page AuthRedirect guards that has no redirect of its own (unlike "/").
const GATED_PATH = '/create-game';

// How long a redirect gets to show up, counted from page load, so it includes
// app start-up. The same window as privacy.spec.ts.
const REDIRECT_WINDOW_MS = 5_000;

// A common phone width, in CSS pixels.
const PHONE_WIDTH = 375;

async function expectSupport(page: Page) {
  await expect(page.getByRole('heading', { level: 1, name: 'Support' })).toBeVisible();
  await expect(page).toHaveTitle('Treachery Support');
}

/** Fails if anything moves the page off /support within the redirect window. */
async function expectToStayOnSupport(page: Page) {
  await page.waitForTimeout(REDIRECT_WINDOW_MS);
  await expect(page).toHaveURL(/\/support$/);
  await expectSupport(page);
}

test.describe('Support page', () => {
  test('opens for a signed-out visitor', async ({ page }) => {
    await page.goto('/support');
    await expectSupport(page);
    await expectToStayOnSupport(page);

    // Control: a gated page still sends the same visitor to sign in, so a
    // window too short to see a redirect can't make the check above pass.
    await page.goto(GATED_PATH);
    await expect(page).toHaveURL(/\/login$/, { timeout: REDIRECT_WINDOW_MS });
  });

  test('opens for a signed-in player', async ({ page }) => {
    await signInAsGuest(page);
    await page.goto('/support');
    await expectSupport(page);
    await expectToStayOnSupport(page);
  });

  test('links to the contact address and the privacy policy', async ({ page }) => {
    await page.goto('/support');
    await expectSupport(page);

    const email = page.getByRole('link', { name: CONTACT_EMAIL, exact: true });
    await expect(email).toHaveAttribute('href', `mailto:${CONTACT_EMAIL}`);

    const policy = page.getByRole('link', { name: 'Privacy Policy', exact: true });
    await expect(policy).toHaveAttribute('href', '/privacy');
    await policy.click();
    await expect(page).toHaveURL(/\/privacy$/);
    await expect(page.getByRole('heading', { level: 1, name: 'Privacy Policy' })).toBeVisible();
  });

  test(`fits a ${PHONE_WIDTH}px-wide screen without scrolling sideways`, async ({ page }) => {
    await page.setViewportSize({ width: PHONE_WIDTH, height: 812 });
    await page.goto('/support');
    await expectSupport(page);

    const layout = await page.getByRole('main').evaluate((main) => {
      // The right edge of everything on the page: every element's box, and
      // every line of text, which can overflow its box without widening it.
      const text = document.createRange();
      text.selectNodeContents(main);
      const boxes = Array.from(main.querySelectorAll('*'), (el) => el.getBoundingClientRect());
      return {
        viewportWidth: window.innerWidth,
        visibleWidth: document.documentElement.clientWidth,
        pageWidth: document.documentElement.scrollWidth,
        contentRight: Math.max(text.getBoundingClientRect().right, ...boxes.map((b) => b.right)),
      };
    });
    expect(layout.viewportWidth).toBe(PHONE_WIDTH);
    // The page doesn't scroll sideways...
    expect(layout.pageWidth).toBeLessThanOrEqual(layout.visibleWidth);
    // ...and nothing runs off its right edge, which React Native Web's
    // ScrollView would clip rather than scroll.
    expect(layout.contentRight).toBeLessThanOrEqual(layout.visibleWidth);
  });
});
