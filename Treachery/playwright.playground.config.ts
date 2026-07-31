import { defineConfig, devices } from '@playwright/test';

/**
 * Config for the manual playtest harness (e2e/playground.spec.ts) — driven by
 * `npm run playtest`, never by CI.
 *
 * Differs from playwright.config.ts in the ways that matter for driving a game
 * by hand rather than asserting on one: windows are visible, there is no test
 * timeout (you decide when you're done), and the viewport is small enough that
 * four to eight windows tile on a laptop screen.
 */
export default defineConfig({
  testDir: './e2e',
  testMatch: '**/playground.spec.ts',
  // No timeout: the spec parks on page.pause() until you dismiss it.
  timeout: 0,
  // Individual assertions during setup should still fail fast rather than hang.
  expect: { timeout: 20_000 },
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: 'list',
  use: {
    baseURL: 'http://localhost:8082',
    headless: false,
    viewport: { width: 820, height: 900 },
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: 'npx serve dist -p 8082 -s --no-clipboard',
    url: 'http://localhost:8082',
    reuseExistingServer: true,
    timeout: 60_000,
  },
});
