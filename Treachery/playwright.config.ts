import { defineConfig, devices } from '@playwright/test';

/**
 * E2E config — see e2e/start-game.spec.ts.
 *
 * Tests are run via `npm run test:e2e`, which wraps this in
 * `firebase emulators:exec` so the auth/firestore/functions emulators
 * are running and torn down around the test invocation.
 *
 * Playwright itself starts a static `serve` for the pre-built `dist/`
 * (built with EXPO_PUBLIC_USE_EMULATOR=true so the bundle points
 * the firebase SDK at the local emulators).
 */
export default defineConfig({
  testDir: './e2e',
  timeout: 60_000,
  expect: { timeout: 10_000 },
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['github'], ['list']] : 'list',
  use: {
    baseURL: 'http://localhost:8082',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: 'npx serve dist -p 8082 -s --no-clipboard',
    url: 'http://localhost:8082',
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
  },
});
