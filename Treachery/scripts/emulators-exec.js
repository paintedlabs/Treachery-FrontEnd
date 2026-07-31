#!/usr/bin/env node
/**
 * Runs a command inside `firebase emulators:exec`, first making sure a Java
 * 21+ runtime is on PATH:  node scripts/emulators-exec.js "<inner command>"
 *
 * firebase-tools >= 14 refuses to start the emulators on Java < 21, and the
 * default `java` on a dev machine here is 17 — so a bare
 * `firebase emulators:exec` in an npm script fails with
 * "firebase-tools no longer supports Java version before 21" unless the
 * developer happens to have exported JAVA_HOME. This wrapper probes for a
 * suitable JDK the same way firestore-tests/scripts/run-rules-tests.js and
 * functions/test/integration/callables/run.sh do, so `npm run test:e2e` and
 * `npm run playtest` work from a fresh shell. On a machine (or CI image)
 * where `java` is already 21+ it is a straight passthrough.
 */

"use strict";

const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const TREACHERY_DIR = path.resolve(__dirname, "..");
const MIN_JAVA_MAJOR = 21;

const innerCommand = process.argv[2];
if (!innerCommand) {
  console.error("usage: node scripts/emulators-exec.js '<command to run inside emulators:exec>'");
  process.exit(2);
}

/** `java -version` prints to stderr, so both streams have to be inspected. */
function javaMajorVersion(javaBin) {
  const res = spawnSync(javaBin, ["-version"], { encoding: "utf8" });
  if (res.error) return null;
  return parseMajor(`${res.stdout || ""}${res.stderr || ""}`);
}

function parseMajor(text) {
  const match = /version "(\d+)(?:\.(\d+))?/.exec(text || "");
  if (!match) return null;
  const major = Number(match[1]);
  // Legacy scheme: 1.8.x means Java 8
  if (major === 1 && match[2] !== undefined) return Number(match[2]);
  return major;
}

/** Candidate JAVA_HOME directories, most preferred first. */
function candidateJavaHomes() {
  const candidates = [];
  if (process.env.JAVA_HOME) candidates.push(process.env.JAVA_HOME);

  // Homebrew keg-only openjdk formulae, highest version first.
  for (const optDir of [
    "/opt/homebrew/opt",
    "/usr/local/opt",
    "/home/linuxbrew/.linuxbrew/opt",
  ]) {
    let entries;
    try {
      entries = fs.readdirSync(optDir).filter((e) => /^openjdk(@\d+)?$/.test(e));
    } catch {
      continue;
    }
    const suffix = (e) => Number(e.split("@")[1] || "0");
    entries.sort((a, b) => suffix(b) - suffix(a));
    for (const entry of entries) {
      candidates.push(path.join(optDir, entry, "libexec/openjdk.jdk/Contents/Home"));
      candidates.push(path.join(optDir, entry));
    }
  }

  // Standard JVM install locations.
  for (const jvmDir of ["/Library/Java/JavaVirtualMachines", "/usr/lib/jvm"]) {
    try {
      for (const entry of fs.readdirSync(jvmDir)) {
        candidates.push(path.join(jvmDir, entry, "Contents/Home"));
        candidates.push(path.join(jvmDir, entry));
      }
    } catch {
      /* directory absent on this platform */
    }
  }

  return candidates;
}

function resolveJavaHome() {
  for (const home of candidateJavaHomes()) {
    const bin = path.join(home, "bin", "java");
    if (!fs.existsSync(bin)) continue;
    const major = javaMajorVersion(bin);
    if (major !== null && major >= MIN_JAVA_MAJOR) return { home, major };
  }
  return null;
}

const env = { ...process.env };
const ambient = javaMajorVersion("java");

if (ambient === null || ambient < MIN_JAVA_MAJOR) {
  const found = resolveJavaHome();
  if (!found) {
    console.error(
      `[emulators] No Java ${MIN_JAVA_MAJOR}+ runtime found (ambient java: ${ambient ?? "none"}). ` +
        "The Firebase emulators require one — install it (e.g. `brew install openjdk@23`) " +
        "or point JAVA_HOME at a suitable JDK."
    );
    process.exit(1);
  }
  env.JAVA_HOME = found.home;
  env.PATH = `${path.join(found.home, "bin")}${path.delimiter}${env.PATH}`;
  console.log(
    `[emulators] ambient java is ${ambient ?? "missing"}; using Java ${found.major} at ${found.home}`
  );
}

const result = spawnSync(
  "npx",
  [
    "--no-install",
    "firebase",
    "emulators:exec",
    "--project=demo-test",
    "--only",
    "auth,firestore,functions",
    "--config=../firebase.json",
    innerCommand,
  ],
  { cwd: TREACHERY_DIR, env, stdio: "inherit" }
);

process.exit(result.status === null ? 1 : result.status);
