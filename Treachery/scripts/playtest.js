#!/usr/bin/env node
/**
 * Interactive launcher for the manual playtest harness:  npm run playtest
 *
 * Asks which game format and how many players to test, then hands off to
 * scripts/emulators-exec.js (Java detection + firebase emulators:exec +
 * the playground Playwright config). The questions are asked BEFORE the
 * emulators start because stdin doesn't survive the emulators:exec chain.
 *
 * Env vars still work and SKIP their prompt, so existing muscle memory and
 * scripted invocations behave exactly as before:
 *
 *   PLAYTEST_MODE=none PLAYTEST_PLAYERS=2 npm run playtest   # no questions
 *   PLAYTEST_LIFE / PLAYTEST_START pass straight through (never prompted)
 *
 * Non-interactive stdin (CI, pipes) never hangs: prompts are skipped and
 * defaults/env apply. PLAYTEST_FORCE_PROMPT=1 forces prompting on piped
 * stdin — a test hook, also handy for driving this script from another tool.
 *
 * Flags: --nobuild  skip the ~30s web rebuild (dist/ must already be an
 *                   emulator build)
 *        --dry-run  resolve and print the config, don't launch anything
 */

"use strict";

const { spawnSync } = require("child_process");
const path = require("path");
const readline = require("readline");

// Format first, players second: the valid player range depends on the format
// (treachery's role table covers 4-8; planechase / life tracker work from 1).
const MODES = [
  { value: "treachery", label: "Treachery", min: 4, max: 8 },
  { value: "treachery_planechase", label: "Treachery + Planechase", min: 4, max: 8 },
  { value: "planechase", label: "Planechase", min: 1, max: 8 },
  { value: "none", label: "Life Tracker", min: 1, max: 8 },
];

const argv = process.argv.slice(2);
const noBuild = argv.includes("--nobuild");
const dryRun = argv.includes("--dry-run");

const interactive = process.stdin.isTTY || process.env.PLAYTEST_FORCE_PROMPT === "1";

/**
 * readline.question drops lines that arrive while no question is pending —
 * with pasted or piped input, everything after the first answer lands between
 * questions and vanishes, and EOF mid-prompt strands the promise (node just
 * exits). This prompter queues every line as it arrives and resolves EOF as
 * "" so unanswered questions fall back to their defaults instead of hanging
 * or dying silently.
 */
function createPrompter() {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: process.stdin.isTTY === true,
  });
  const queued = [];
  const waiting = [];
  let closed = false;
  rl.on("line", (line) => {
    const waiter = waiting.shift();
    if (waiter) waiter(line);
    else queued.push(line);
  });
  rl.on("close", () => {
    closed = true;
    while (waiting.length) waiting.shift()("");
  });
  return {
    ask(question) {
      process.stdout.write(question);
      if (queued.length) return Promise.resolve(queued.shift());
      if (closed) return Promise.resolve("");
      return new Promise((resolve) => waiting.push(resolve));
    },
    close() {
      if (!closed) rl.close();
    },
  };
}

async function promptMode(prompter) {
  const menu = MODES.map((m, i) => `  ${i + 1}) ${m.label}`).join("\n");
  for (;;) {
    const answer = (
      await prompter.ask(`Which format do you want to test?\n${menu}\nFormat [1]: `)
    ).trim();
    if (answer === "") return MODES[0];
    const index = Number.parseInt(answer, 10) - 1;
    if (MODES[index]) return MODES[index];
    // Also accept the value or label typed out ("planechase", "Life Tracker").
    const byName = MODES.find(
      (m) =>
        m.value === answer.toLowerCase() ||
        m.label.toLowerCase() === answer.toLowerCase(),
    );
    if (byName) return byName;
    console.log(`  Please answer 1-${MODES.length}.`);
  }
}

async function promptPlayers(prompter, mode) {
  const def = Math.max(4, mode.min);
  for (;;) {
    const answer = (
      await prompter.ask(`How many players? (${mode.min}-${mode.max}) [${def}]: `)
    ).trim();
    if (answer === "") return def;
    const n = Number.parseInt(answer, 10);
    if (Number.isInteger(n) && n >= mode.min && n <= mode.max) return n;
    console.log(`  ${mode.label} supports ${mode.min}-${mode.max} players here.`);
  }
}

async function resolveConfig() {
  const env = process.env;
  let modeValue = env.PLAYTEST_MODE;
  let players = env.PLAYTEST_PLAYERS;

  // Env-provided values are passed through untouched (the spec has its own
  // guard rails, and PLAYTEST_START=lobby legitimately allows counts the
  // prompt wouldn't offer). Only PROMPTED answers get range-checked.
  if (interactive && (!modeValue || !players)) {
    const prompter = createPrompter();
    try {
      let mode = MODES.find((m) => m.value === modeValue);
      if (!modeValue) {
        mode = await promptMode(prompter);
        modeValue = mode.value;
      }
      if (!players) {
        // If the mode came from env but isn't recognized, fall back to a
        // permissive 1-8 range rather than guessing wrong bounds.
        players = String(
          await promptPlayers(prompter, mode ?? { label: "This mode", min: 1, max: 8 }),
        );
      }
    } finally {
      prompter.close();
    }
  }

  return {
    mode: modeValue || "treachery",
    players: players || "4",
  };
}

(async () => {
  const config = await resolveConfig();
  const label =
    MODES.find((m) => m.value === config.mode)?.label ?? config.mode;
  console.log(
    `\n[playtest] ${config.players} players · ${label}` +
      `${process.env.PLAYTEST_START ? ` · start=${process.env.PLAYTEST_START}` : ""}` +
      `${process.env.PLAYTEST_LIFE ? ` · life=${process.env.PLAYTEST_LIFE}` : ""}\n`,
  );

  if (dryRun) {
    console.log(`[playtest] dry-run: ${JSON.stringify(config)}`);
    return;
  }

  const inner = noBuild
    ? "playwright test --config=playwright.playground.config.ts"
    : "npm run build:web:emulator && playwright test --config=playwright.playground.config.ts";

  const result = spawnSync(
    "node",
    [path.join(__dirname, "emulators-exec.js"), inner],
    {
      stdio: "inherit",
      env: {
        ...process.env,
        PLAYTEST_MODE: config.mode,
        PLAYTEST_PLAYERS: String(config.players),
      },
    },
  );
  process.exit(result.status === null ? 1 : result.status);
})();
